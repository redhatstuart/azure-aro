---
title: Use a customer-managed key to encrypt Azure disks in OpenShift Container Platform in IaaS
description: Bring your own keys (BYOK) to encrypt OCP Data disks.
services: openshift
ms.topic: article
ms.date: 05/21/2020

---

# Bring your own keys (BYOK) with Azure disks in Red Hat OpenShift Container Platform (IaaS)

Azure Storage encrypts all data in a storage account at rest. By default, data is encrypted with Microsoft-managed keys which includes OS and data disks. For additional control over encryption keys, you can supply [customer-managed keys][customer-managed-keys] to use for encryption at rest for the data disks in your OpenShift clusters.

## Before you begin

* This article assumes that you have deployed OpenShift Container Platform using IaaS on Azure and **not** Azure Red Hat OpenShift (ARO).

* You must enable soft delete and purge protection for *Azure Key Vault* when using Key Vault to encrypt managed disks.

* You are logged in to your OpenShift cluster with *oc* as a global cluster-admin user (kubeadmin).

* You have installed OCP using the Installer-Provisioned-Infrastructure (IPI) and have access to the 'terraform.tfvars.json' file which was created upon build.

* You have 'jq' installed.

```azurecli-interactive
# Optionally retrieve Azure region short names for use on upcoming commands
az account list-locations
```
## Declare your variables & determine your active Azure subscription
You should configure the variables below to whatever may be appropriate for your deployment.  Make sure you use the same Azure Region for the Disk BYOK Encryption Set & Key Vault Resource Group that you did for your OpenShift Container Platform cluster.
```
azureDC="eastus"                   # The short name of the Azure Data Center you have deployed OCP in
cryptRG="ocp-cryptRG"              # The name of the resource group to be created to manage the Azure Disk Encryption set and Key Vault
desName="ocp-des"                  # Your Azure Disk Encryption Set
vaultName="ocp-keyvault-1"         # Your Azure Key Vault
vaultKeyName="myCustomOCPKey"      # The name of the key to be used within your Azure Key Vault

subId="$(az account list -o tsv | grep True | awk '{print $2}')"
```

## Create an Azure Key Vault instance
Use an Azure Key Vault instance to store your keys.  You can optionally use the Azure portal to [Configure customer-managed keys with Azure Key Vault][byok-azure-portal]

Create a new *resource group*, a new *Key Vault* instance (with soft delete and purge protection) and create a *new key* within the vault to store your own custom key. 

```azurecli-interactive
# Create new resource group in a supported Azure region to store the Azure Disk Encryption Set and Azure Key Vault
az group create -l $azureDC -n $cryptRG

# Create an Azure Key Vault resource in a supported Azure region
az keyvault create -n $vaultName -g $cryptRG --enable-purge-protection true --enable-soft-delete true

# Create the actual key within the Azure Key Vault
az keyvault key create --vault-name $vaultName --name $vaultKeyName --protection software
```

## Create an Azure Disk Encryption Set instance
```azurecli-interactive
# Retrieve the Key Vault Id and store it in a variable
keyVaultId=$(az keyvault show --name $vaultName --query [id] -o tsv)

# Retrieve the Key Vault key URL and store it in a variable
keyVaultKeyUrl=$(az keyvault key show --vault-name $vaultName --name $vaultKeyName  --query [key.kid] -o tsv)

# Create an Azure Disk Encryption Set
az disk-encryption-set create -n $desName -g $cryptRG --source-vault $keyVaultId --key-url $keyVaultKeyUrl
```

## Grant the Azure Disk Encryption Set access to Key Vault
Use the *Azure Disk Encryption Set* and *Resource Group* you created in the prior steps and grant the resource access to the Azure Key Vault.

```azurecli-interactive
# Determine the Azure Disk Encryption Set AppId value and set it a variable
desIdentity=$(az disk-encryption-set show -n $desName -g $cryptRG --query [identity.principalId] -o tsv)

# Update keyvault security policy settings
az keyvault set-policy -n $vaultName -g $cryptRG --object-id $desIdentity --key-permissions wrapkey unwrapkey get

# Ensure the Azure Disk Encryption Set can read the contents of the Azure Key Vault
az role assignment create --assignee $desIdentity --role Reader --scope $keyVaultId
```

## Obtain other IDs required for role assignments
```
# Obtain the OCP cluster ID assigned by the IPI
ocpClusterId="$(jq -r '.cluster_id' terraform.tfvars.json)"

# Set the name of the Azure Resource Group created by the IPI
ocpGroup="$ocpClusterId-rg"

# Set the name of the Azure Managed Service Identity created by the IPI
msiName="$ocpClusterId-identity"

# Determine the OCP MSI AppId
ocpAppId="$(az identity show -n $msiName -g $ocpGroup -o tsv --query [clientId])"

# Determine the Resource ID for the Azure Disk Encryption Set and Azure Key Vault Resource Group
encryptRGResourceId="$(az group show -n $cryptRG -o tsv --query [id])"

# Determine the Resoruce ID for the OCP Resource Group
ocpRGResourceId="$(az group show -n $ocpGroup -o tsv --query [id])"
```

## Implement additinal role assignments required for BYOK encryption
```azurecli-interactive
# Assign the MSI AppID 'Reader' permission over the Azure Disk Encryption Set & Key Vault Resource Group
az role assignment create --assignee $ocpAppId --role Reader --scope $encryptRGResourceId

# Assign the AppID of the Disk Encryption Set 'Reader' permission over the OCP Resource Group
az role assignment create --assignee $desIdentity --role Reader --scope $ocpRGResourceId
```

## Encrypt your OCP cluster data disk

You can encrypt the OCP data disks with your own keys.

Create storage class configuration files that utilize the *Azure Disk Encryption Set* previously created. Afterwards, execute the 'sed' commands which follow to make the appropriate variable substitutions. 

## Create the k8s Storage Class to be used for encrypted Premium & Standard disks
```
# Premium Disks
cat > encrypted-byok-azure-premium-disk.yaml<< EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: managed-premium-byok
provisioner: kubernetes.io/azure-disk
parameters:
  skuname: Premium_LRS
  kind: Managed
  diskEncryptionSetID: "/subscriptions/subId/resourceGroups/cryptRG/providers/Microsoft.Compute/diskEncryptionSets/desName"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF

# Standard Disks
cat > encrypted-byok-azure-standard-disk.yaml<< EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: managed-standard-byok
provisioner: kubernetes.io/azure-disk
parameters:
  skuname: Standard_LRS
  kind: Managed
  diskEncryptionSetID: "/subscriptions/subId/resourceGroups/cryptRG/providers/Microsoft.Compute/diskEncryptionSets/desName"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF
```
## Perform variable substitutions within the Storage Class configuration
```
# Insert your current active subscription ID into the configuration
sed -i "s/subId/$subId/g" encrypted-byok-azure-premium-disk.yaml
sed -i "s/subId/$subId/g" encrypted-byok-azure-standard-disk.yaml

# Replace the name of the Resource Group which contains Azure Disk Encryption set and Key Vault
sed -i "s/cryptRG/$cryptRG/g" encrypted-byok-azure-premium-disk.yaml
sed -i "s/cryptRG/$cryptRG/g" encrypted-byok-azure-standard-disk.yaml

# Replace the name of the Azure Disk Encryption Set
sed -i "s/desName/$desName/g" encrypted-byok-azure-premium-disk.yaml
sed -i "s/desName/$desName/g" encrypted-byok-azure-standard-disk.yaml
```
Next, run this deployment in your OCP cluster to apply the storage class configuration:
```
# Update cluster with the new storage classes
oc apply -f encrypted-byok-azure-premium-disk.yaml
oc apply -f encrypted-byok-azure-standard-disk.yaml
```
## Deploy a test Pod utilizing the BYOK disk encryption storage class
```
# Create a pod which uses a persistent volume claim referencing the new storage class
cat > test-pvc.yaml<< EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: azure-managed-disk-byok
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: managed-standard-byok
  resources:
    requests:
      storage: 1Gi
---
kind: Pod
apiVersion: v1
metadata:
  name: mypod-des
spec:
  containers:
  - name: mypod-des
    image: nginx:1.15.5
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 250m
        memory: 256Mi
    volumeMounts:
    - mountPath: "/mnt/azure"
      name: volume
  volumes:
    - name: volume
      persistentVolumeClaim:
        claimName: azure-managed-disk-byok
EOF
```
## Apply the Test Pod configuration file
```
# Apply the test pod configuration file and set the PVC UID as a variable to query in Azure later
pvcUid="$(oc apply -f test-pvc.yaml -o json | jq -r '.items[0].metadata.uid')"

# Determine the full Azure Disk name
pvcName="$ocpClusterId-dynamic-pvc-$pvcUid"
```
## Verify 
At this point, a Pod should be created which creates a persistent volume claim which references the BYOK storage class. Running the following command will validate that the PVC has been deployed as expected:
```azurecli-interactive
# Describe the OpenShift cluster-wide persistent volume claims
oc describe pvc

# Verify with Azure that the disk is encrypted with a customer-managed key
az disk show -n $pvcName -g $ocpGroup -o json --query [encryption]
```

## Limitations

* BYOK is only currently available in GA and Preview in certain [Azure regions][supported-regions]
* BYOK OS Disk Encryption supported with OCP 4.4 + Kubernetes version 1.17 and above   
* Available only in regions where BYOK is supported

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
