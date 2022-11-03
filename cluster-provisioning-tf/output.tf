output "get_instance_privateIP2" {
  description = "The PrivateIP of the Instance"
  value       = "${google_compute_instance.private-management-vm.network_interface[0].network_ip}/32"
}