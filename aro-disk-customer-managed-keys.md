---
title: Use a customer-managed key to encrypt Azure disks in OpenShift Container Platform in IaaS
description: Bring your own keys (BYOK) to encrypt OCP Data disks.
services: container-service
ms.topic: article
ms.date: 01/12/2020

---

# Bring your own keys (BYOK) with Azure disks in Red Hat OpenShift Container Platform (IaaS)

Azure Storage encrypts all data in a storage account at rest. By default, data is encrypted with Microsoft-managed keys which includes OS and data disks. For additional control over encryption keys, you can supply [customer-managed keys][customer-managed-keys] to use for encryption at rest for the data disks for your OpenShift clusters.

## Before you begin

* This article assumes that you have deployed OpenShift Container Platform using IaaS on Azure and not ARO.

* You must enable soft delete and purge protection for *Azure Key Vault* when using Key Vault to encrypt managed disks.

* You are logged in to your OpenShift cluster as a global cluster-admin user (kubeadmin).

```azurecli-interactive
# Optionally retrieve Azure region short names for use on upcoming commands
az account list-locations
```
## Declare your variables & determine your active Azure subscription

```azurecli-interactive
azureDC="eastus"                   # The short name of the Azure Data Center you have deployed OCP in
cryptRG="ocp-cryptRG"              # The name of the resource group to be created to manage the disk encryption set and keyvault
desName="ocp-des"                  # Your Azure Disk Encryption Set
vaultName="ocp-keyvault-2"         # Your Azure KeyVault
vaultKeyName="myCustomersOCPKey"   # The name of the key to be used within your Azure KeyVault

subId="$(az account list -o tsv |grep True |awk '{print $2}')"
```

## Create an Azure Key Vault instance

Use an Azure Key Vault instance to store your keys.  You can optionally use the Azure portal to [Configure customer-managed keys with Azure Key Vault][byok-azure-portal]

Create a new *resource group*, then create a new *Key Vault* instance and enable soft delete and purge protection.  Ensure you use the same region and resource group names for each command.

```azurecli-interactive
# Create new resource group in a supported Azure region
az group create -l $azureDC -n $cryptRG

# Create an Azure Key Vault resource in a supported Azure region
az keyvault create -n $vaultName -g $cryptRG --enable-purge-protection true --enable-soft-delete true

# Create the actual key within the Azure Key Vault
az keyvault key create --vault-name $vaultName --name $vaultKeyName --protection software
```

## Create an instance of a DiskEncryptionSet
```azurecli-interactive
# Retrieve the Key Vault Id and store it in a variable
keyVaultId=$(az keyvault show --name $vaultName --query [id] -o tsv)

# Retrieve the Key Vault key URL and store it in a variable
keyVaultKeyUrl=$(az keyvault key show --vault-name $vaultName --name $vaultKeyName  --query [key.kid] -o tsv)

# Create a DiskEncryptionSet
az disk-encryption-set create -n $desName -g $cryptRG --source-vault $keyVaultId --key-url $keyVaultKeyUrl
```

## Grant the DiskEncryptionSet access to key vault

Use the DiskEncryptionSet and resource groups you created on the prior steps, and grant the DiskEncryptionSet resource access to the Azure Key Vault.

```azurecli-interactive
# Retrieve the DiskEncryptionSet value and set a variable
desIdentity=$(az disk-encryption-set show -n $desName -g $cryptRG --query [identity.principalId] -o tsv)

# Update security policy settings
az keyvault set-policy -n $vaultName -g $cryptRG --object-id $desIdentity --key-permissions wrapkey unwrapkey get

# Assign the reader role
az role assignment create --assignee $desIdentity --role Reader --scope $keyVaultId
```



## Encrypt your OCP cluster data disk

You can encrypt the OCP data disks with your own keys.


```azurecli-interactive
# Retrieve your Azure Subscription Id from id property as shown below
az account list
```

```
someuser@Azure:~$ az account list
[
  {
    "cloudName": "AzureCloud",
    "id": "666e66d8-1e43-4136-be25-f25bb5de5893",
    "isDefault": true,
    "name": "MyAzureSubscription",
    "state": "Enabled",
    "tenantId": "3ebbdf90-2069-4529-a1ab-7bdcb24df7cd",
    "user": {
      "cloudShellID": true,
      "name": "someuser@azure.com",
      "type": "user"
    }
  }
]
```

Create a file called **byok-azure-disk.yaml** that contains the following information.  Replace myAzureSubscriptionId, myResourceGroup, and myDiskEncrptionSetName with your values, and apply the yaml.  Make sure to use the resource group where your DiskEncryptionSet is deployed.  If you use the Azure Cloud Shell, this file can be created using vi or nano as if working on a virtual or physical system:

```
kind: StorageClass
apiVersion: storage.k8s.io/v1  
metadata:
  name: hdd
provisioner: kubernetes.io/azure-disk
parameters:
  skuname: Standard_LRS
  kind: managed
  diskEncryptionSetID: "/subscriptions/{myAzureSubscriptionId}/resourceGroups/{myResourceGroup}/providers/Microsoft.Compute/diskEncryptionSets/{myDiskEncryptionSetName}"
```
Next, run this deployment in your AKS cluster:
```azurecli-interactive
# Get credentials
az aks get-credentials --name myAksCluster --resource-group myResourceGroup --output table

# Update cluster
kubectl apply -f byok-azure-disk.yaml
```

## Limitations

* BYOK is only currently available in GA and Preview in certain [Azure regions][supported-regions]
* OS Disk Encryption supported with Kubernetes version 1.17 and above   
* Available only in regions where BYOK is supported
* Encryption with customer-managed keys currently is for new AKS clusters only, existing clusters cannot be upgraded
* AKS cluster using Virtual Machine Scale Sets are required, no support for Virtual Machine Availability Sets


## Next steps

Review [best practices for AKS cluster security][best-practices-security]

<!-- LINKS - external -->

<!-- LINKS - internal -->
[az-extension-add]: /cli/azure/extension#az-extension-add
[az-extension-update]: /cli/azure/extension#az-extension-update
[best-practices-security]: /azure/aks/operator-best-practices-cluster-security
[byok-azure-portal]: /azure/storage/common/storage-encryption-keys-portal
[customer-managed-keys]: /azure/virtual-machines/windows/disk-encryption#customer-managed-keys
[key-vault-generate]: /azure/key-vault/key-vault-manage-with-cli2
[supported-regions]: /azure/virtual-machines/windows/disk-encryption#supported-regions
