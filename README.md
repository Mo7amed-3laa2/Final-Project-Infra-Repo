# Final Project Infrastructure repo:

DevOps Challenge Demo which is aim to build a full GKE Private Cluster protected by IAP and deploying simple application to this cluster using load balancer service.

Note that the Commits related to the project building process.

#  1. Create The GCP Project & Configure it's billing.

![1](https://user-images.githubusercontent.com/32172405/198904247-028ba2fb-6632-4617-bad9-a1d7012f8f53.png)

## 2. Create the Terraform code to Provision the infrastructure:

  1)  Create the main VPC --> my-project-vpc
  
  2)  Create two subnets:
  * Management Subnet --> management-subent
  Private subnet contain
   a private vm --> management-vm that is the only vm that can communicate with the GKE cluster (will be created later).
   
*  Restricted Subnet --> restricted-subent
  a private subnet contain a private cluster --> my-project-cluster and this cluster can't be accessing from any where except the management-vm.
  ### Terraform Provisioning:
``` bash
$ terraform init 
$ terraform apply 
> yes (confirm)
```

![image](https://user-images.githubusercontent.com/32172405/198904291-efc01b2f-83c5-406c-ae1a-66eb19ec9b84.png)

![image](https://user-images.githubusercontent.com/32172405/198904308-1737447a-5a74-4940-81a3-69bde231e4e4.png)

![image](https://user-images.githubusercontent.com/32172405/198904336-cac78865-7a40-4cf1-bbc5-993a754ded74.png)
 
 **- The infrastructure provisioning complete.** 
![image](https://user-images.githubusercontent.com/32172405/198904898-034233e4-3f6d-499e-862c-2563a339f81a.png)

## 3. Dockerize a custom jenkins image.
Dockerize a custom jenkins image include
kubectl, docker, git, jdk, ...
``` bash
$ docker build . --tag <docker-id>/<image-name>:<tag>
```
Then push the image to the docker hub
``` bash
$ docker push  <docker-id>/<image-name>:<tag>
```


Connect to the Management VM to configure it to be able to connect to the cluster and run the deployment files (remember that the connection can be only done through the IAP):

``` bash
$ gcloud compute ssh --zone "......" "private-management-vm" --tunnel-through-iap --project "....."
``` 
 At the Management VM:

``` bash
$ kubectl cluster-info
```
![image](https://user-images.githubusercontent.com/32172405/198906004-244fea91-a156-4fc9-a805-550f082a45c3.png)

## 4. Deploying jenkins-master.

At the Management VM copy and run the deployment files, then getting jenkins-master IP:

``` bash
$ kubectl apply -f pv.yml
$ kubectl apply -f jenkins-sa.yml
$ kubectl apply -f jenkins-deployment.yml
$ kubectl apply -f jenkins-service-lb.yml
$ kubectl get services -n jenkins
```
![image](https://user-images.githubusercontent.com/32172405/199645535-b8d31ed4-ad02-490d-beac-890168512c60.png)


then get the jenkins secrets:

``` bash
$ kc get pods -n jenkins
$ kc logs pod/<pod-name> -n jenkins
```
Finally configure the jenkins master, install needed plugins and add the needed credentials.

Now the jenekins master ready for piplines (next part).

http://35.193.191.162:8080

user: mohamed
password: toor
