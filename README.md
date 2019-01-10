# Example use of Azure Kubernetes Service

## Objectives
The aim of this repository is to guide a person into creating a Kubernetes cluster in Azure and deploying and exposing a simple application for the first time.
It introduces a number of technologies and presumptions :)
* Access to a Azure Subscription , with initially *owner* level access
* Docker Desktop , Docker Compose
* Azure Cli 2.x
* Kubernetes CLI kubectl
* Helm CLI
* NodeJS (+npm)

This probably only works on a Mac or Linux based local machine , although you mileage may vary.

## Docker
Right lets build our Docker image with our NodeJS sample code.
You'll need Docker (shock!) installed
If you wish feel free to play with the NodeJS code and HTML and adjust as necessary.

Run docker build with a tag that you'll remember in this repo that you have already checked out locally (right?).

Replace "nodeapps" with whatever you environment or service is trying to do, Its quite likely this will already be taken :)

```
docker build --rm -f "Dockerfile" -t nodejs-example-app:latest .
```

Run the nodeJS application locally and see it work its magic. 
```
docker run --rm -it -p 3000:3000/tcp nodejs-example-app:latest
```
You should be able to hit http://localhost:3000 and see this:

```
Sample NodeJS App.
Nothing to see here move along.
Version x 
```

Now stop it! 
```
docker stop nodejs-example-app
```

Now lets do the same with docker compose (again check http://localhost:3000 )
```
docker-compose -f "docker-compose.yaml" up -d --build
docker-compose -f "docker-compose.yaml" down
```

Now lets tag the Docker Image also
```
docker tag nodejs-example-app_web:latest
```

Ok so we have built an docker image based on the [DockerFile] in this repo (You can play with this file locally again to add more items) , started a local running version of the application and looked at it using a local browser.

# Azure Container registry 
We need to now store our freshly baked image somewhere so that it can be retrieved from and deployed into a container service.For that we will use the Azure Container Registry (ACR)

You'll need to install [azure cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

You'll need to setup Service principle  
https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli?view=azure-cli-latest
also this
https://docs.microsoft.com/en-us/azure/container-registry/container-registry-auth-aks

### Login
Example using the Azure CLI to create a service principal:
```
az ad sp create-for-rbac --name nodeapps-app-sp --password PASSWORD
```

Output example:
Store the output somewhere safe ( pref in Azure Vault* ) and use in active shell
```
{
  "appId": "<returns appId>",
  "displayName": "<a descriptive name>",
  "name": "http://<a descriptive name>",
  "password": "<returns password>",
  "tenant": "<returns tenant>"
}
```

To sign again in use the Azure CLI :
```
az login --service-principal --username APP_ID --password PASSWORD --tenant TENANT_ID
```

*OR* shell (use the az_login.bash template and adjust as required)
```

export AZ_APP_ID="<value>"
export AZ_CLIENT_SECRET="<value>"
export AZ_TENANT_ID="<value>"
export AZ_SUBSCRIPTION_ID="<value>"

az login --service-principal -u "${AZ_APP_ID}" --password "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" > /dev/null
az account set -s "${AZ_SUBSCRIPTION_ID}" > /dev/null

```

Do 'source' your interactive shell , or you'll login with your current active user.

### Create ACR
First create an Azure resource group to put the ACR in
```
az group create --name az-nodeapps-nonprod-weu-acr-rg --location "West Europe"
```

Next create the actual Azure Container Registry with
```
az acr create --resource-group az-nodeapps-nonprod-weu-acr-rg --name nodeappsweureg --sku Basic
```

You should be able to test the login

```
az acr login --name nodeappsweureg
```

Also can be tested through Docker login too:
```
docker login nodeappsweureg.azurecr.io
        Username: ndapweureg
        Password:
```
### Docker Tag 
We need to tag the image so that it can be controlled in ACR 
Tag the image for ACR
```
docker tag nodejs-example-app_web:latest nodeappsweureg.azurecr.io/examples/nodejs-example-app
```

You may need to enable the administrator user account for the ACS that you created.
```
az acr update --name nodeappsweureg --admin-enabled true
```

Push your Docker image to the ACR that you created
```
docker push nodeappsweureg.azurecr.io/examples/nodejs-example-app
```

You should now be able to 'see' and list if your image is in Azure ACR

```
az acr show --resource-group az-nodeapps-nonprod-weu-acr-rg --name nodeappsweureg --query "id" --output tsv
```

# Azure Kubernetes Service

Right, now we should try and deploy the image into something to run it!

## To deploy Azure AKS in shell

Create resource group (notice the naming convention :-) ...)

```
az group create --name az-nodeapps-nonprod-weu-aks2-rg --location "west europe"
```

Create AKS cluster inside the group created.
If you dont use service principal , this command will create one for you ...

```
az aks create --resource-group az-nodeapps-nonprod-weu-aks2-rg --name az-nodeapps-nonprod-weu-k8s-2 --node-count 1 --enable-addons monitoring --generate-ssh-keys
```

This will create a 'default' cluster , which is at the moment 1 Node, 2 cores with 7 gig Mem , and (usually) not the latest Kubernetes version , this will take a little bit of time. This command should also add any local SSH Keys to the cluster. Also will create a logAnalytics workspace too.

Add (merge) credentials to local .kube/config
```
az aks get-credentials --resource-group az-nodeapps-nonprod-weu-aks2-rg --name az-nodeapps-nonprod-weu-k8s-2
```
See aks-auth.bash for more info.
```
AKS_RESOURCE_GROUP=az-nodeapps-nonprod-weu-aks2-rg
AKS_CLUSTER_NAME=az-nodeapps-nonprod-weu-k8s-2
az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv
```

If you have [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl) and [kubectx](https://github.com/ahmetb/kubectx) installed you will be able to list the new cluster

```
kubectx
az-nodeapps-nonprod-weu-k8s
az-nodeapps-nonprod-weu-k8s-2
az-nonprod-weu-aks-0001
```

```
kubectl get nodes
NAME                       STATUS    ROLES     AGE       VERSION
aks-nodepool1-40547294-0   Ready     agent     17m       v1.9.11
```

### Bootstrap services
Great now we need to bootstrap some additional services ...


Before you can deploy Helm in an RBAC-enabled AKS cluster, you need a service account and role binding for the Tiller service. For more information on securing Helm / Tiller in an RBAC enabled cluster, see Tiller, Namespaces, and RBAC. If your AKS cluster is not RBAC enabled, skip this step.
```
kubectl apply -f helm-rbac.yaml
```

[helm](https://github.com/helm/helm#install) cli locally is required 

Install tiller into your AKS cluster (server side of Helm)
```
helm init --service-account tiller
```
--- later note to try with TLS

Create sample namespace
```
kubectl apply -f sample-namespace.yaml
```

Describe namespace and view limit ranges
```
kubectl describe namespace example-nodejs-dev-ns
kubectl describe limitrange
```

To deploy (and delete) application chart....
```
cd ..
helm install ./nodejs-example-chart --namespace example-nodejs-dev-ns
helm delete wobbly-termite
```
Note the deployment name 'wobbly-termite' will be diffrent for you

To see events in current namespace (including errors)
```
kubectl get events --sort-by=.metadata.creationTimestamp
```

To portforward from your AKS cluster and view sample application on a local browser
```
kubectl port-forward nodejs-example-chart-deployment-55dfccccf6-wsb9d 3000
```
again the actual deployment name will be different.
You should see the remote application deployed on AKS and forwarded to your local machine http://localhost:3000

# Expose the application to the world

We need to create an ingress controller

There is a helm template already for this
```
helm install stable/nginx-ingress --namespace kube-system --set controller.replicaCount=2
```

check on the deployment (this can take a while)

```
kubectl get service -l app=nginx-ingress --namespace kube-system
```

apply ingress rule
```
kubectl apply -f example-nodejs-ingress.yaml
```

Check on endpoints ...
```
kubectl get endpoints nodejs-example-chart-service
```

```
pruning-goose-nginx-ingress-controller        LoadBalancer   10.0.58.67     x.x.x.x    80:30341/TCP,443:31503/TCP   28d
pruning-goose-nginx-ingress-default-backend   ClusterIP      10.0.197.160   <none>          80/TCP                       28d
```

Eventually there should now be a public IP address in the output from the commands above 
you should be able to hit it externally using the IP http://x.x.x.x
(x value should be a real number )

Finally cheeky way to test connectivity internally , get a shell!
```
kubectl run -i --tty load-generator --image=busybox /bin/sh
# or
kubectl exec -it --tty load-generator-5c4d59d5dd-qczwf -- /bin/sh
```
and hit it once or forever ...
```
while true; do wget -q -O- http://nodejs-example-chart-deployment.example-nodejs-dev-ns.svc.cluster.local; done
```



## TODO
Shall we add ELK stack?
Shall we add opentracing ?
Shall we try this all through jenkins?

To Be Continued...
```
helm install --name my-release stable/jenkins --namespace jenkins
```