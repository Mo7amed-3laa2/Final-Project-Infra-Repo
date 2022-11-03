# Create the Service Account && Assign it to my project
resource "google_service_account" "my-project-sa" {
  account_id   = "my-project-sa"
  display_name = "Project Service Account"
}

# Assign needed roles to the service accout
resource "google_project_iam_binding" "my-project-sa-roles" {
  project    = "mohamed-alaa-eldeen"
  role       = "roles/container.admin"
  members    = ["serviceAccount:${google_service_account.my-project-sa.email}"]
  depends_on = [google_service_account.my-project-sa]
}

# Enable Needed API's -----------------------------------------------------------------#
variable "gcp_apis_list" {
  description = "The list of apis necessary for the project"
  type        = list(string)
  default     = ["compute.googleapis.com", "container.googleapis.com", "vmwareengine.googleapis.com", "artifactregistry.googleapis.com"]
}
resource "google_project_service" "apis-enabler" {
  for_each                   = toset(var.gcp_apis_list)
  project                    = "mohamed-alaa-eldeen"
  service                    = each.key
  disable_dependent_services = true
}
#------------------------------------------------------------------------------------
# Create The Project VPC
resource "google_compute_network" "my-project-vpc" {
  name                    = "my-project-vpc"
  depends_on              = [google_project_service.apis-enabler]
  auto_create_subnetworks = false
}

# Create --- Management Subnet ------------------------------------------------------------------------------------ #
resource "google_compute_subnetwork" "management-subnetwork" {
  name                     = "management-subnetwork"
  ip_cidr_range            = "10.0.0.0/24"
  region                   = "us-central1"
  network                  = google_compute_network.my-project-vpc.id
  private_ip_google_access = true

}
# create a router for NAT GW used in ---> Management Subnet ---- #
resource "google_compute_router" "my-project-router" {
  name    = "my-project-router"
  region  = google_compute_subnetwork.management-subnetwork.region
  network = google_compute_network.my-project-vpc.id

  bgp {
    asn = 64514
  }
}
# create a NAT GW to allow private subnet access internet used in ---> Management Subnet ---- #
resource "google_compute_router_nat" "my-project-nat" {
  name                               = "my-project-nat"
  router                             = google_compute_router.my-project-router.name
  region                             = google_compute_router.my-project-router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.management-subnetwork.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
# Firewall rule to prevent the private VM from any accessing except IAP
resource "google_compute_firewall" "allow-iap-only" {
  name        = "allow-iap-only"
  network     = google_compute_network.my-project-vpc.id
  description = "Allow only IAP to access the VM and prevent any other accessing"

  allow {
    protocol = "tcp"
    ports    = ["80", "22"]
  }
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
}
# Create the Management private VM used by ---> Management Subnet---- #
resource "google_compute_instance" "private-management-vm" {
  name                      = "private-management-vm"
  machine_type              = "e2-medium"
  zone                      = "us-central1-a"
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.my-project-vpc.id
    subnetwork = google_compute_subnetwork.management-subnetwork.id
  }
  # assign a service account to this vm
  service_account {
    email  = google_service_account.my-project-sa.email
    scopes = ["cloud-platform"]
  }

  metadata = { # there are better way to do this, make a script file and call it. / # export and source  to clear gcloud warning message
    startup-script = <<-EOF
      sudo apt-get update
      sudo apt-get install -y kubectl
      sudo apt-get install google-cloud-sdk-gke-gcloud-auth-plugin
      export USE_GKE_GCLOUD_AUTH_PLUGIN=True
      source .bashrc
      gcloud container clusters get-credentials my-project-cluster --zone us-central1-a --project mohamed-alaa-eldeen
  EOF
  }
}

# Create --- Restricted Subnet for the GKE cluster -------------------------------------------------------------------------------- #
resource "google_compute_subnetwork" "restricted-subnetwork" {
  name          = "restricted-subnetwork"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.my-project-vpc.id
}

# Create --- The Private GKE Cluster -------------------------------------------------------------------------------- #
resource "google_container_cluster" "my-project-cluster" {
  name       = "my-project-cluster"
  location   = "us-central1-a"
  network    = google_compute_network.my-project-vpc.id
  subnetwork = google_compute_subnetwork.management-subnetwork.id

  # Removes the implicit default node pool, recommended when using # google_container_node_pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = ""
    services_secondary_range_name = ""
  }

  # to restrict the controlling of the cluster on the Management VM only.
  master_authorized_networks_config {
    #enabled = true
    cidr_blocks {
      cidr_block   = "${google_compute_instance.private-management-vm.network_interface[0].network_ip}/32" #google_compute_subnetwork.management-subnetwork.ip_cidr_range # AUTHORIZED_NETWORK_RANGE
      display_name = "Management VM Network"
    }
  }
}

# Node pool to run some Linux-only Kubernetes Pods.
resource "google_container_node_pool" "cluster-preemptible-nodes" {
  name       = "cluster-preemptible-nodes"
  location   = "us-central1-a"
  cluster    = google_container_cluster.my-project-cluster.name
  node_count = 3

  node_config {
    preemptible  = true
    machine_type = "e2-medium"

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.my-project-sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}