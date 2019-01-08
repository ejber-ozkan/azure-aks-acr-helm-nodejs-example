#!/bin/bash
echo "Assigns the default created AKS service principal to the ACR (so it can read from it)."
AKS_RESOURCE_GROUP=az-nodeapps-nonprod-weu-aks2-rg
AKS_CLUSTER_NAME=az-nodeapps-nonprod-weu-k8s-2
ACR_RESOURCE_GROUP=az-nodeapps-nonprod-weu-reg-rg
ACR_NAME=nodeappsweureg

# Get the id of the service principal configured for AKS
CLIENT_ID=$(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv)

# Get the ACR registry resource id
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)

# Create role assignment
az role assignment create --assignee $CLIENT_ID --role Reader --scope $ACR_ID
