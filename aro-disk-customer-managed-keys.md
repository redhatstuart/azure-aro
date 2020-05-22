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

* You have installed OCP using the Installer-Provisioned-Infrastructure (IPI) and have access to the 'terraform.tfvars.json' file.

* You have 'jq' installed.

```azurecli-interactive
# Optionally retrieve Azure region short names for use on upcoming commands
az account list-locations
```
## Declare your variables & determine your active Azure subscription

```azurecli-interactive
azureDC="eastus"                   # The short name of the Azure Data Center you have deployed OCP in
cryptRG="ocp-cryptRG"              # The name of the resource group to be created to manage the Azure Disk Encryption set and KeyVault
desName="ocp-des"                  # Your Azure Disk Encryption Set
vaultName="ocp-keyvault-1"         # Your Azure KeyVault
vaultKeyName="myCustomOCPKey"      # The name of the key to be used within your Azure KeyVault

subId="$(az account list -o tsv |grep True |awk '{print $2}')"
```

## Create an Azure Key Vault instance

Use an Azure Key Vault instance to store your keys.  You can optionally use the Azure portal to [Configure customer-managed keys with Azure Key Vault][byok-azure-portal]

Create a new *resource group*, a new *Key Vault* instance (with soft delete and purge protection) and create a new key within the vault to store your own custom key.  Make sure you use the same Azure Region for the Disk Encryption Set & KeyVault Resource Group that you did for your OpenShift Container Platform cluster.

```azurecli-interactive
# Create new resource group in a supported Azure region to store the Azure Disk Encryption Set and Azure KeyVault
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

## Obtain other IDs required for role assignments
```azurecli-interactive
# Obtain the OCP cluster ID assigned by the IPI
ocpClusterId="$(jq -r '.cluster_id' terraform.tfvars.json)"

# Set the name of the Azure Resource Group created by the IPI
ocpGroup="$ocpClusterId-rg"

# Set the name of the Azure Managed Service Identity created by the IPI
msiName="$ocpClusterId-identity"

# Determine the OCP MSI AppId
ocpAppId="$(az identity show -n $msiName -g $ocpGroup -o tsv --query [clientId])"

# Determine the Resource ID for the Azure Disk Encryption Set and Azure KeyVault Resource Group
encryptRGResourceId="$(az group show -n $cryptRG -o tsv --query [id])"

# Determine the Resoruce ID for the OCP Resource Group
ocpRGResourceId="$(az group show -n $ocpGroup -o tsv --query [id])"
```

## Implement additinal role assignments required for BYOK encryption
```azurecli-interactive
# Assign the MSI AppID 'Reader' permission over the Disk Encryption Set & KeyVault Resource Group
az role assignment create --assignee $ocpAppId --role Reader --scope $encryptRGResourceId

# Assign the AppID of the Disk Encryption Set 'Reader' permission over the OCP Resource Group
az role assignment create --assignee $desIdentity --role Reader --scope $ocpRGResourceId
```

## Encrypt your OCP cluster data disk

You can encrypt the OCP data disks with your own keys.

Create a file called **byok-azure-disk.yaml** that contains the following information. After you save the file, execute the 'sed' commands which follow to make the appropriate variable substitutions. If you use the Azure Cloud Shell, this file can be created using vi or nano as if working on a virtual or physical system:

## Create the k8s Storage Class to be used for encrypted disks
```
cat > byok-azure-disk.yaml<< EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: encrypted-disk-des
provisioner: kubernetes.io/azure-disk
parameters:
  skuname: Standard_LRS
  kind: managed
  diskEncryptionSetID: "/subscriptions/subId/resourceGroups/cryptRG/providers/Microsoft.Compute/diskEncryptionSets/desName"
EOF
```
## Replace your subscription ID
```
sed -i "s/subId/$subId/g" byok-azure-disk.yaml
```
## Replace the name of the Resource Group which contains Azure Disk Encryption set and KeyVault
```
sed -i "s/cryptRG/$cryptRG/g" byok-azure-disk.yaml
```
## Replace the name of the Resource Group which contains Azure Disk Encryption set and KeyVault
```
sed -i "s/desName/$desName/g" byok-azure-disk.yaml
```
Next, run this deployment in your OCP cluster:
```azurecli-interactive
# Update cluster
oc apply -f byok-azure-disk.yaml
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
