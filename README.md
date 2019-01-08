# Lets build our Docker image with our NodeJS sample code.
You'll need Docker (shock!) installed

Run docker build with a tag that you'll remember in this repo that you have already checked out (right?).

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

# Lets create an Azure Container registry 

You'll need to install [azure cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

You'll need to setup Service principle  
https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli?view=azure-cli-latest
also this
https://docs.microsoft.com/en-us/azure/container-registry/container-registry-auth-aks

Example:
```
az ad sp create-for-rbac --name nodeapps-app-sp --password PASSWORD
```

Output example:
Store the output somewhere safe ( pref in Azure Vault ) and use in active shell
```
{
  "appId": "<returns appId>",
  "displayName": "<a descriptive name>",
  "name": "http://<a descriptive name>",
  "password": "<returns password>",
  "tenant": "<returns tenant>"
}
```

To sign in :
```
az login --service-principal --username APP_ID --password PASSWORD --tenant TENANT_ID
```

or shell (use the az_login.bash template and adjust as required)
```

export AZ_APP_ID="<value>"
export AZ_CLIENT_SECRET="<value>"
export AZ_TENANT_ID="<value>"
export AZ_SUBSCRIPTION_ID="<value>"

az login --service-principal -u "${AZ_APP_ID}" --password "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" > /dev/null
az account set -s "${AZ_SUBSCRIPTION_ID}" > /dev/null


```

Do 'source' your interactive shell , or you'll login with your current active user.

First create an Azure resource group to put the ACR in
```
az group create --name az-nodeapps-nonprod-weu-acr-rg --location "West Europe"
```

Create Azure Container Registry with
```
az acr create --resource-group az-nodeapps-nonprod-weu-acr-rg --name nodeappsweureg --sku Basic
```
Test the login

```
az acr login --name nodeappsweureg
```

You can test it through Docker login too:
```
docker login nodeappsweureg.azurecr.io
        Username: ndapweureg
        Password:
```

Tag the image for ACR
```
docker tag nodejs-example-app_web:latest nodeappsweureg.azurecr.io/examples/nodejs-example-app
```

Enable the administrator user account for an Azure Container Registry.
```
az acr update --name nodeappsweureg --admin-enabled true
```

Push your Docker image to ACR
```
docker push nodeappsweureg.azurecr.io/examples/nodejs-example-app
```

See if your Image is in Azure ACR

```
az acr show --resource-group az-nodeapps-nonprod-weu-acr-rg --name nodeappsweureg --query "id" --output tsv
```

Right, now we should try and deploy the image into something to run it!

# Run book to deploy Azure AKS in shell

Create resource group (naming convention...)

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

Great now we need to bootstrap some services ...


Before you can deploy Helm in an RBAC-enabled AKS cluster, you need a service account and role binding for the Tiller service. For more information on securing Helm / Tiller in an RBAC enabled cluster, see Tiller, Namespaces, and RBAC. If your AKS cluster is not RBAC enabled, skip this step.
```
kubectl apply -f helm-rbac.yaml
```

[helm](https://github.com/helm/helm#install) cli locally is required 
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

To portforward and view sample application
```
kubectl port-forward nodejs-example-chart-deployment-55dfccccf6-wsb9d 3000
```
again the actual deployment name will be different.

# Chapter two learning

Create an ingress controller

```
helm install stable/nginx-ingress --namespace kube-system --set controller.replicaCount=2
```

check on the deployment

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

Cheeky way to test connectivity internally , get a shell!
```
kubectl run -i --tty load-generator --image=busybox /bin/sh
# or
kubectl exec -it --tty load-generator-5c4d59d5dd-qczwf -- /bin/sh
```
and hit it once or forever ...
```
while true; do wget -q -O- http://nodejs-example-chart-deployment.example-nodejs-dev-ns.svc.cluster.local; done
```


# chapter 3
Shall we add ELK stack?
Shall we add opentracing ?
Shall we try this all through jenkins?

To Be Continued...
```
helm install --name my-release stable/jenkins --namespace jenkins
```