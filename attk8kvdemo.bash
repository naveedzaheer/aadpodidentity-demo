# "objectId": "8a05c999-fafc-44a7-b8b2-33bc86cba5d0"
# "appId": "657798d8-8b1f-420a-8ad4-6268fe4114f9",
# "displayName": "azure-cli-2019-04-15-16-25-07",
# "name": "http://azure-cli-2019-04-15-16-25-07",
# "password": "174fec77-dac3-4312-840b-3c13286a6b99",
# "tenant": "f0e35cf1-b7b9-452d-bcf8-76d522dc0c1d"

# Create AKS Cluster
# export AKS_RESOURCE_GROUP=attk8kvdemo-rg
# export LOCATION=eastus  
# export AKS_CLUSTER_NAME=aks7690  
# export ACR_NAME=attk8kvdemoacr  
# export MANAGED_IDENTITY_NAME1=attk8kvdemouser1
# export MANAGED_IDENTITY_NAME2=attk8kvdemouser2
# export MANAGED_IDENTITY_NAMEGW=appgwContrIdentity7690
# export KEYVAULT_NAME1=attk8kvdemo1-kv
# export KEYVAULT_NAME2=attk8kvdemo2-kv
# export SP_APP_ID=657798d8-8b1f-420a-8ad4-6268fe4114f9

export AKS_RESOURCE_GROUP=attk8demo-rg
export LOCATION=eastus  
export AKS_CLUSTER_NAME=aksf009  
export ACR_NAME=attk8demoacr  
export MANAGED_IDENTITY_NAME1=attk8demouser1
export MANAGED_IDENTITY_NAME2=attk8demouser2
export MANAGED_IDENTITY_NAMEGW=appgwContrIdentityf009
export KEYVAULT_NAME1=attk8demo1-kv
export KEYVAULT_NAME2=attk8demo2-kv
export SP_APP_ID=657798d8-8b1f-420a-8ad4-6268fe4114f9

# GetAKS Cluster Identity
az aks get-credentials -n $AKS_CLUSTER_NAME -g $AKS_RESOURCE_GROUP

kubectl get nodes

az acr create --resource-group $AKS_RESOURCE_GROUP --name $ACR_NAME --sku basic

az role assignment create --assignee $SP_APP_ID --role Contributor --scope $(az acr show --name $ACR_NAME --resource-group $AKS_RESOURCE_GROUP --query "id" --output tsv)

#################################
### - Infrastructure Tasks Start
#################################

# Create Azure Key Vault-1
az keyvault create -n $KEYVAULT_NAME1 -g $AKS_RESOURCE_GROUP -l $LOCATION

az keyvault secret set --vault-name $KEYVAULT_NAME1 -n Secret1 --value SuparSecretValue1-Production

az keyvault secret set --vault-name $KEYVAULT_NAME1 -n Secret2 --value SuparSecretValue2-Production

# Create Azure Key Vault-2
az keyvault create -n $KEYVAULT_NAME2 -g $AKS_RESOURCE_GROUP -l $LOCATION

az keyvault secret set --vault-name $KEYVAULT_NAME2 -n Secret1 --value X1-Prod

az keyvault secret set --vault-name $KEYVAULT_NAME2 -n Secret2 --value X2-Prod

# Tasks for Azure Managed Identity-1
# Create Azure Managed Identity
az identity create -n $MANAGED_IDENTITY_NAME1 -g $AKS_RESOURCE_GROUP

# Grant the Managed Identity "Reader" role on the Key Vault
az role assignment create --role "Reader" --assignee $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME1 --query "principalId" --output tsv) --scope $(az keyvault show --resource-group $AKS_RESOURCE_GROUP --name $KEYVAULT_NAME1 --query "id" --output tsv)

# Grant "Get" and "List" permissions on secrets in the Key Vault
az keyvault set-policy -n $KEYVAULT_NAME1 --secret-permissions get list --spn $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME1 --query "clientId" --output tsv)

# Assign the AKS Service Principal to the "Managed Identity Operator" role for the Managed Identity create in the previous steps
az role assignment create --role "Managed Identity Operator" --assignee $SP_APP_ID --scope $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME1 --query "id" --output tsv)

# Tasks for Azure Managed Identity-2
# Create Azure Managed Identity
az identity create -n $MANAGED_IDENTITY_NAME2 -g $AKS_RESOURCE_GROUP

# Grant the Managed Identity "Reader" role on the Key Vault
az role assignment create --role "Reader" --assignee $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME2 --query "principalId" --output tsv) --scope $(az keyvault show --resource-group $AKS_RESOURCE_GROUP --name $KEYVAULT_NAME2 --query "id" --output tsv)

# Grant "Get" and "List" permissions on secrets in the Key Vault
az keyvault set-policy -n $KEYVAULT_NAME2 --secret-permissions get list --spn $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME2 --query "clientId" --output tsv)

# Assign the AKS Service Principal to the "Managed Identity Operator" role for the Managed Identity create in the previous steps
az role assignment create --role "Managed Identity Operator" --assignee $SP_APP_ID --scope $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME2 --query "id" --output tsv)

# Tasks for Azure Managed Identity for GW
# Grant the Managed Identity "Contributor" role on the Key Vault
az role assignment create --role "Contributor" --assignee $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAMEGW --query "principalId" --output tsv) --scope $(az group show --resource-group $AKS_RESOURCE_GROUP --name $AKS_RESOURCE_GROUP --query "id" --output tsv)

# Assign the AKS Service Principal to the "Managed Identity Operator" role for the Managed Identity create in the previous steps
az role assignment create --role "Managed Identity Operator" --assignee $SP_APP_ID --scope $(az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAMEGW --query "id" --output tsv)

#################################
### - Infrastructure Tasks End
#################################

#################################
### - Services Tasks Start
#################################

# Install AAD Pod Identity CRD (RBAC version)
kubectl create -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml

# Create the AzureIdentity for Identity 1
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAME1` -v MANAGED_IDENTITY_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME1 --query \"id\" --output tsv` -v CLIENT_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME1 --query \"clientId\" --output tsv` '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$MANAGED_IDENTITY_ID/, MANAGED_IDENTITY_ID); sub(/\$CLIENT_ID/, CLIENT_ID); print }' aad-pod-identity.template.yaml > aad-pod-identity1.yaml

# Create the AzureIdentity for Identity 2
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAME2` -v MANAGED_IDENTITY_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME2 --query \"id\" --output tsv` -v CLIENT_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME2 --query \"clientId\" --output tsv` '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$MANAGED_IDENTITY_ID/, MANAGED_IDENTITY_ID); sub(/\$CLIENT_ID/, CLIENT_ID); print }' aad-pod-identity.template.yaml > aad-pod-identity2.yaml

# Create the AzureIdentity for Identity GW
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAMEGW` -v MANAGED_IDENTITY_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAMEGW --query \"id\" --output tsv` -v CLIENT_ID=`az identity show --resource-group $AKS_RESOURCE_GROUP --name $MANAGED_IDENTITY_NAMEGW --query \"clientId\" --output tsv` '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$MANAGED_IDENTITY_ID/, MANAGED_IDENTITY_ID); sub(/\$CLIENT_ID/, CLIENT_ID); print }' aad-pod-identity.template.yaml > aad-pod-identitygw.yaml

kubectl apply -f aad-pod-identity1.yaml
kubectl apply -f aad-pod-identity2.yaml
kubectl apply -f aad-pod-identitygw.yaml

# Create the AzureIdentityBinding for Identity 1
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAME1` -v SELECTOR="aad-demo-app1" '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$SELECTOR/, SELECTOR); print }' aad-identity-binding.template.yaml > aad-identity-binding1.yaml

# Create the AzureIdentityBinding for Identity 2
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAME2` -v SELECTOR="aad-demo-app2" '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$SELECTOR/, SELECTOR); print }' aad-identity-binding.template.yaml > aad-identity-binding2.yaml

# Create the AzureIdentityBinding for Identity GW
awk -v MANAGED_IDENTITY_NAME=`echo $MANAGED_IDENTITY_NAMEGW` -v SELECTOR="aad-demo-appgw" '{ sub(/\$MANAGED_IDENTITY_NAME/, MANAGED_IDENTITY_NAME); sub(/\$SELECTOR/, SELECTOR); print }' aad-identity-binding.template.yaml > aad-identity-bindinggw.yaml

kubectl apply -f aad-identity-binding1.yaml
kubectl apply -f aad-identity-binding2.yaml
kubectl apply -f aad-identity-bindinggw.yaml

# Setup the App Gateway
# install helm
kubectl create serviceaccount --namespace kube-system tiller-sa
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller-sa
helm init --tiller-namespace kube-system --service-account tiller-sa
helm repo add application-gateway-kubernetes-ingress https://azure.github.io/application-gateway-kubernetes-ingress/helm/
helm repo update

# create the helm-config.yaml file
helm install -f helm-config.yaml application-gateway-kubernetes-ingress/ingress-azure

# create the guestbook-all-in-one.yaml file and setup guest book app
kubectl apply -f guestbook-all-in-one.yaml

# create the ing-guestbook.yaml
kubectl apply -f ing-guestbook.yaml

# ACR build the sample app 1
awk -v KEYVAULT_NAME=`echo $KEYVAULT_NAME1` '{ sub(/\$KEYVAULT_NAME/, KEYVAULT_NAME); print }' appsettings.json > tmp && mv tmp appsettings.json

awk -v ACR_NAME=`echo $ACR_NAME` -v APP_NAME="keyvault-demo1" -v POD_BINDING="aad-demo-app1" -v PORT_NUMBER="8081" '{ sub(/\$ACR_NAME/, ACR_NAME); sub(/\$APP_NAME/, APP_NAME); sub(/\$POD_BINDING/, POD_BINDING); sub(/\$PORT_NUMBER/, PORT_NUMBER); print }' keyvault-demo-full.template.yaml > keyvault-demo1.yaml

az acr build --registry $ACR_NAME --image keyvault-demo1:latest .

# ACR build the sample app 1
awk -v KEYVAULT_NAME=`echo $KEYVAULT_NAME2` '{ sub(/\$KEYVAULT_NAME/, KEYVAULT_NAME); print }' appsettings.json > tmp && mv tmp appsettings.json

awk -v ACR_NAME=`echo $ACR_NAME` -v APP_NAME="keyvault-demo2" -v POD_BINDING="aad-demo-app2" -v PORT_NUMBER="8082" '{ sub(/\$ACR_NAME/, ACR_NAME); sub(/\$APP_NAME/, APP_NAME); sub(/\$POD_BINDING/, POD_BINDING); sub(/\$PORT_NUMBER/, PORT_NUMBER); print }' keyvault-demo-full.template.yaml > keyvault-demo2.yaml

az acr build --registry $ACR_NAME --image keyvault-demo2:latest .

# Deploy app 1 to AKS
kubectl apply -f keyvault-demo1.yaml

# Deploy app 2 to AKS
kubectl apply -f keyvault-demo2.yaml

# Create KV Felx Volume
kubectl create -f https://raw.githubusercontent.com/Azure/kubernetes-keyvault-flexvol/master/deployment/kv-flexvol-installer.yaml

# build and create demokvpod.yaml
kubectl create -f demokvpod.yaml

# Now you can access the value of those secrets using the following command:
kubectl exec -it aks-kv-sample-pod cat kv/Secret2

