# Example use of Azure Kubernetes Service

## Objectives
The aim of this repository is to guide a person into creating a Kubernetes cluster in Azure and deploying and exposing a simple application for the first time.
It introduces a number of technologies and presumptions :-)
* Access to a Azure Subscription , with initially *owner* level access
* Docker Desktop , Docker Compose
* Azure Cli 2.x
* Kubernetes CLI kubectl
* Helm CLI
* NodeJS (+npm)

This probably only works on a Mac or Linux based local machine , although you mileage may vary.

## Dockerize NodeJS app
Right lets build a Docker image from our amazing NodeJS application [code](server.js).
You'll need Docker (shock!) installed
If you wish feel free to play with the NodeJS code and HTML and adjust as necessary.

Run docker build with a tag that you'll remember in this repo that you have already checked out locally (right?).

Replace ``nodeapps`` prefix that you see in this doc and in any files in this repo with whatever you environment or service is trying to do, Its quite likely this will already be taken :)

```bash
docker build --rm -f "Dockerfile" -t nodejs-example-app:latest .
```

Run the nodeJS application locally and see it work its magic. 
```bash
docker run --rm -it -p 3000:3000/tcp nodejs-example-app:latest
```
You should be able to hit http://localhost:3000 in your local browser and see this:

```html
Sample NodeJS App.
Nothing to see here move along.
Version x 
```

Now stop it! 
```bash
docker stop nodejs-example-app
```

Now lets do the same with docker compose [docker-compose.yaml](docker-compose.yaml)

(again check http://localhost:3000 ) 
```bash
docker-compose -f "docker-compose.yaml" up -d --build
docker-compose -f "docker-compose.yaml" down
```
Although in this example we will not have multiple container application for this example  , docker-compose will work with one app too.

Now lets tag the Docker Image also
```bash
docker tag nodejs-example-app_web:latest
```

Ok so we have built a docker image based on the [Dockerfile](Dockerfile) in this repo (You can play with this file locally again to add more items to the image if you wish) , started a local running version of the application and looked at it using a local browser.

# Azure Container Registry 
We need to now store our freshly baked image somewhere so that it can be retrieved from and deployed into a container service.For that we will use the Azure Container Registry (ACR)

You'll need to install [azure cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

You'll need to setup Service principle  
https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli?view=azure-cli-latest
also this
https://docs.microsoft.com/en-us/azure/container-registry/container-registry-auth-aks

### Login to Azure
Example using the Azure CLI to create a service principal:

```bash
az ad sp create-for-rbac --name nodeapps-app-sp --password PASSWORD
```

Output example:
Store the output somewhere safe ( pref in Azure Vault* ) and use in active shell 

```json
{
  "appId": "<returns appId>",
  "displayName": "<a descriptive name>",
  "name": "http://<a descriptive name>",
  "password": "<returns password>",
  "tenant": "<returns tenant>"
}
```

To sign again in use the Azure CLI :
```bash
az login --service-principal --username APP_ID --password PASSWORD --tenant TENANT_ID
```

*OR* use a shell script ,use the [az_login.bash](az_login.bash.tpl) template , rename to .bash and adjust as required)

```bash

export AZ_APP_ID="<value>"
export AZ_CLIENT_SECRET="<value>"
export AZ_TENANT_ID="<value>"
export AZ_SUBSCRIPTION_ID="<value>"

az login --service-principal -u "${AZ_APP_ID}" --password "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" > /dev/null
az account set -s "${AZ_SUBSCRIPTION_ID}" > /dev/null

```

Do 'source' your interactive shell , or you'll login with your current active user.

### Create ACR
OK now that we can login to Azure through a command line,we can now create an Azure resource group to put the ACR in
*note* replace ``nodeapps`` name prefix with your own acr name

```bash
az group create --name az-nodeapps-nonprod-weu-acr-rg --location "West Europe"
```

Next create the actual Azure Container Registry with

```bash
az acr create --resource-group az-nodeapps-nonprod-weu-acr-rg --name nodeappsweureg --sku Basic
```

Notice the naming convention used for resources in azure , its always adviceable to come up with something that makes it as clear as possible on what it does,where it does it , why it does it and for whom.
Below is one I try to follow usually:

``az-nodeapps-nonprod-weu-acr-rg``

``<cloudprovider-<environment>-<region>-<service>-<resourcetype>``

You should be able to test the login to your new shiny Repository 

```bash
az acr login --name nodeappsweureg
```

Also can be tested through Docker login too:

```bash
docker login nodeappsweureg.azurecr.io
        Username: nodeappsweureg
        Password:
```

### Docker Tag 
We need to tag the image so that it can be controlled in ACR

Tag the image for ACR

```bash
docker tag nodejs-example-app_web:latest nodeappsweureg.azurecr.io/examples/nodejs-example-app
```

You may need to enable the administrator user account for the ACR that you created.

```bash
az acr update --name nodeappsweureg --admin-enabled true
```

Push your Docker image to the ACR that you created

```bash
docker push nodeappsweureg.azurecr.io/examples/nodejs-example-app
```

You should now be able to 'see' and list if your image  in Azure ACR

```bash
az acr show --resource-group az-nodeapps-nonprod-weu-acr-rg --name nodeappsweureg --query "id" --output tsv
```

# Azure Kubernetes Service

Right! 
Now we should try and deploy the image into something to run it!

## To deploy an Azure AKS Cluster

Using shell cli commands create resource group (notice the naming convention :-) ...)

```bash
az group create --name az-nodeapps-nonprod-weu--rg --location "west europe"
```

Create AKS cluster inside the group created.
If you dont use service principal , this command will create one for you ...

```bash
az aks create --resource-group az-nodeapps-nonprod-weu-aks-rg --name az-nodeapps-nonprod-weu-k8s-2 --node-count 1 --enable-addons monitoring --generate-ssh-keys
```

This will create a 'default' cluster , which is at the moment 1 Node, 2 cores with 7 gig Memory , and (usually) not the latest Kubernetes version , this will take a little bit of time. This command should also add any local SSH Keys to the cluster. Also will create a logAnalytics workspace too.

Add (merge) credentials to local .kube/config

```bash
az aks get-credentials --resource-group az-nodeapps-nonprod-weu-aks-rg --name az-nodeapps-nonprod-weu-k8s-2

```

See [aks-auth.bash](Azure/aks-auth.bash) for more info.

```bash
AKS_RESOURCE_GROUP=az-nodeapps-nonprod-weu-aks-rg
AKS_CLUSTER_NAME=az-nodeapps-nonprod-weu-k8s-2
az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv
```

If you have [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl) and [kubectx](https://github.com/ahmetb/kubectx) installed you will be able to list the new cluster

```bash
kubectx
az-nodeapps-nonprod-weu-k8s
az-nodeapps-nonprod-weu-k8s-2
az-nonprod-weu-aks-0001
```

```bash
kubectl get nodes
NAME                       STATUS    ROLES     AGE       VERSION
aks-nodepool1-40547294-0   Ready     agent     17m       v1.9.11
```

### Bootstrap services
Great now we need to bootstrap and add some additional services into the new cluster...

Before you can deploy Helm in an RBAC-enabled AKS cluster, you need a service account and role binding for the Tiller service. For more information on securing Helm / Tiller in an RBAC enabled cluster, see Tiller, Namespaces, and RBAC. If your AKS cluster is not RBAC enabled, skip this step.

[helm-rbac.yaml](Azure/helm-rbac.yaml)

```bash
kubectl apply -f helm-rbac.yaml
```

[helm](https://github.com/helm/helm#install) cli locally is required 

Install tiller into your AKS cluster (server side of Helm)

```bash
helm init --service-account tiller
```
--- TODO: to try with TLS

### Create namespace
To create a sample namespace [sample-namespace.yaml](Azure/sample-namespace.yaml)

```bash
kubectl apply -f sample-namespace.yaml
```

This namespace example yaml has a number of configuration items that are worth looking through and playing with , the key highlights being:
* The *LimitRange* for pods and container deployments in that namespace.
* The *ResourceQuota* for things like *Storage* , *pod* totals,*cpu* and *memory* limits
* *NetworkPolicy* that deny all by default and only allows port 3000 for this example application and also allow pods to communicate between themselves with the same label.

If you experiment with the values in LimitRange against the values requested in the Helm Chart [values.yaml](nodejs-example-chart/values.yaml) you should be able to see what happens when you try to deploy it into the namespace if resource limits are not met or available.

Describe namespace and view limit ranges
```bash
kubectl describe namespace example-nodejs-dev-ns
kubectl describe limitrange
```

### Deploy Chart
Helm makes it easier for someone to deploy,upgrade and delete helm chart of an application using the giving values in the [values.yaml](nodejs-example-chart/values.yaml)

```bash
cd ..
helm install ./nodejs-example-chart --namespace example-nodejs-dev-ns
#helm delete wobbly-termite
```
Note the deployment name 'wobbly-termite' will be different for you

To see events in current namespace (including errors)

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

To port forward from your AKS cluster and the view sample application on a local browser

```bash
kubectl port-forward nodejs-example-chart-deployment-55dfccccf6-wsb9d 3000
```
again the actual deployment name will be different.

You should see the remote application deployed on AKS and forwarded to your local machine http://localhost:3000

### Expose the application to the world

To expose the application to the world we need to create an ingress controller that allows inbound traffic from the internet into our cluster and forwards on requests to the application where its running inside the cluster.

There is a public helm template already for this that uses the web service nginx

```bash
helm install stable/nginx-ingress --namespace kube-system --set controller.replicaCount=2
```

We can check on the progress of the deployment (this can take a while as it will generate a resource in Azure)

```bash
kubectl get service -l app=nginx-ingress --namespace kube-system
```

We can now apply our rules to allow ingress through and into our applications 
with Applying an ingress rule (see file [example-nodejs-ingress.yaml](example-nodejs-ingress.yaml))

```bash
kubectl apply -f example-nodejs-ingress.yaml
```

This will simply add the internal rule to allow inbound traffic to flow from nginx external facing port into internal port 3000 on which the service app is running
```yaml
...
          serviceName: nodejs-example-chart-service
          servicePort: 3000
...
```

Check on the endpoints being created ...

```bash
kubectl get endpoints nodejs-example-chart-service
```

should see something like this:

```bash
pruning-goose-nginx-ingress-controller        LoadBalancer   10.0.58.67     x.x.x.x    80:30341/TCP,443:31503/TCP   28d
pruning-goose-nginx-ingress-default-backend   ClusterIP      10.0.197.160   <none>          80/TCP                       28d
```

Eventually there should now be a public available IP address in the output from the commands above 
you should be able to hit it externally using the IP http://x.x.x.x
(x value should be a real number )

You can if you wish test connectivity internally , get a shell!

```bash
kubectl run -i --tty load-generator --image=busybox /bin/sh
# or
kubectl exec -it --tty load-generator-5c4d59d5dd-qczwf -- /bin/sh
```

and hit your application internally once or forever , this should pave the way for app to app communications...

```bash
while true; do wget -q -O- http://nodejs-example-chart-deployment.example-nodejs-dev-ns.svc.cluster.local; done
```

### TODO
Shall we add ELK stack?
Shall we add opentracing ?
Shall we try this all through jenkins?

To Be Continued...
```
helm install --name my-release stable/jenkins --namespace jenkins
```