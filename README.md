# AAD Pod Identity Overview

When pods need access to other Azure services, such as Cosmos DB, Key Vault, or Blob Storage, the pod needs access credentials. These access credentials could be defined with the container image or injected as a Kubernetes secret, but need to be manually created and assigned. Often, the credentials are reused across pods, and aren't regularly rotated.

Managed identities for Azure resources let you automatically request access to services through Azure AD. You don't manually define credentials for pods, instead they request an access token in real time, and can use it to access only their assigned services. In AKS, two components are deployed by the cluster operator to allow pods to use managed identities:

AAD Pod Identity also allows admins to switch underlying identities at runtime without developers making any changes to the application.

There are two required components to enable aad pod identity:

- Managed Identity Controller (MIC) - The controller is responsible for the binding of Azure identities to the pods.
- Node Managed Identity (NMI) - Intercepts incoming request for pods and calls back into Azure to acquire access tokens from AAD. This allows communication with the Azure APIs on behalf of the Azure identity.

The example below describes the workflow that uses managed service identity to request access to Azure SQL:

1. Cluster Operator creates azureIdentity referencing a MSI
2. Cluster Operator creates azureIdentityBinding
3. MIC watches AzureIdentityBinding and Pods, then creates a azureAssignedIdentity
4. MIC watches pods and assigns MSI to nodes where the pod is scheduled
5. Pod uses ADAL to acquire token
6. The call is then picked up by NMI and uses the pod name to find identity assigned to it
7. NMI calls the nodes MSI endpoint to acquire token on behalf of the pod

![AAD Pod Identity](img/pod-identities.png)

## AAD Pod Identity Demo

Note: Variable values that begin with __ (two underscores) should be populated from the previous command's output. Other values can be named whatever makes sense.

## Create AKS Cluster

```sh
export AKS_RESOURCE_GROUP=[AKS_RESOURCE_GROUP]
export LOCATION=westus  
export AKS_CLUSTER_NAME=[AKS_CLUSTER_NAME]  
export ACR_NAME=[ACR_NAME]  
export KEYVAULT_NAME=[KEYVAULT_NAME]

az ad sp create-for-rbac --skip-assignment

export SP_APP_ID=[__APP_ID]
export SP_PASSWORD=[__PASSWORD]

az group create -n $AKS_RESOURCE_GROUP -l $LOCATION

az aks get-versions -l $LOCATION

az aks create -n $AKS_CLUSTER_NAME -g $AKS_RESOURCE_GROUP --kubernetes-version [__K8S_VERSION] --service-principal $SP_APP_ID --client-secret $SP_PASSWORD --generate-ssh-keys -l $LOCATION --node-count 3 --enable-addons monitoring --no-wait

az aks list -o table

az aks get-credentials -n $AKS_CLUSTER_NAME -g $AKS_RESOURCE_GROUP

kubectl get nodes
```

## Create ACR

```sh
az acr create --resource-group $AKS_RESOURCE_GROUP --name $ACR_NAME --sku basic

az role assignment create --assignee $SP_APP_ID --role Contributor --scope $(az acr show --name $ACR_NAME --resource-group $AKS_RESOURCE_GROUP --query "id" --output tsv)
```

## Create Azure Key Vault

```sh
az keyvault create -n $KEYVAULT_NAME -g $AKS_RESOURCE_GROUP -l $LOCATION

az keyvault secret set --vault-name $KEYVAULT_NAME -n Secret1 --value SuparSecretValue1-Production

az keyvault secret set --vault-name $KEYVAULT_NAME -n Secret2 --value SuparSecretValue2-Production
```

## Install AAD Pod Identity CRD (RBAC version)

```sh
kubectl create -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
```

## Create Azure Managed Identity

```sh
export MANAGED_IDENTITY_NAME=[MANAGED_IDENTITY_NAME]

az identity create -n $MANAGED_IDENTITY_NAME -g $AKS_RESOURCE_GROUP
```

## Grant the Managed Identity "Reader" role on the Key Vault

```sh
az role assignment create --role "Reader" --assignee $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query "principalId" --output tsv) --scope $(az keyvault show --resource-group $AKS_RESOURCE_GROUP --name $KEYVAULT_NAME --query "id" --output tsv)
```  

## Grant "Get" and "List" permissions on secrets in the Key Vault

```sh
az keyvault set-policy -n $KEYVAULT_NAME --secret-permissions get list --spn $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query "clientId" --output tsv)
```

## Assign the AKS Service Principal to the "Managed Identity Operator" role for the Managed Identity create in the previous steps

```sh
az role assignment create --role "Managed Identity Operator" --assignee $SP_APP_ID --scope $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query "id" --output tsv)
```

## Create the AzureIdentity and AzureIdentityBinding

```sh
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAME` -v MANAGED_IDENTITY_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query \"id\" --output tsv` -v CLIENT_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query \"clientId\" --output tsv` '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$MANAGED_IDENTITY_ID/, MANAGED_IDENTITY_ID); sub(/\$CLIENT_ID/, CLIENT_ID); print }' aad-pod-identity.template.yaml > aad-pod-identity.yaml

kubectl apply -f aad-pod-identity.yaml

awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAME` -v SELECTOR="aad-demo-app" '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$SELECTOR/, SELECTOR); print }' aad-identity-binding.template.yaml > aad-identity-binding.yaml

kubectl apply -f aad-identity-binding.yaml
```  

## OPTIONAL - Test Locally

```sh
dotnet user-secrets set "Secret1" "SuparSecretValue1-Development"

dotnet user-secrets set "Secret2" "SuparSecretValue2-Development"

dotnet run
```

## ACR build the sample app

```sh
awk -v KEYVAULT_NAME=`echo $KEYVAULT_NAME` '{ sub(/\$KEYVAULT_NAME/, KEYVAULT_NAME); print }' appsettings.json > tmp && mv tmp appsettings.json

awk -v ACR_NAME=`echo $ACR_NAME` '{ sub(/\$ACR_NAME/, ACR_NAME); print }' keyvault-demo.template.yaml > keyvault-demo.yaml

az acr build --registry $ACR_NAME --image keyvault-demo:latest .
```

## Deploy app to AKS

```sh
kubectl apply -f ./keyvault-demo.yaml
```
