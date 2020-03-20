# Azure Red Hat Openshift (ARO) Deployment Code / Scripts

## Azure Red Hat OpenShift 3.11

* aro-311-deploy.json
* aro-311-deploy.params.json

These ARM templates can be used to deploy the latest version of Azure Red Hat OpenShift 3.11. Support for the following has been added based on customer demand:
```
* Peering of Azure vnets / enablement of VPN connectivity / Private clusters
* Integration with Azure Monitoring to provide container application metrics
```
To deploy ARO 3.11 you will need to customize the parameters file per your Azure credentials and execute the following commands using the Azure Linux CLI, or clicking on the link below. The build takes roughly 15-20 minutes.
```
* az group create -n <resourcegroup> -l <azuredatacenter>
* az group deployment create -g <resourcegroup> --template-file aro-311-deploy.json --parameters aro-311-deploy.params.json
```

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjmo808%2farm-aro43%2fmasteru%2Fazuredeploy.json" target="_blank">
<img src="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.png"/>
</a>

<hr>

## Azure Red Hat OpenShift 4.x

<h3>aro-build.sh</h3>
<hr>
This script will deploy Azure Red Hat OpenShift 4.x and create the necessary group/network infrastructure required. The process takes roughly 35 minutes. Until the 'az aro' command becomes GA within the Azure Linux CLI, you must ensure your Azure CLI has the extension included: <strong>az extension add -n aro --index https://az.aroapp.io/preview</strong> and continue to keep it updated: <strong>az extension update -n aro --index https://az.aroapp.io/preview</strong>
<br><br>

The usage is as follows:<br>
**./aro-build.sh** to create an ARO 4.x cluster with a standard aroapp.io domain.<br>
**./aro-build.sh blah.foo.com** to create an ARO 4.x cluster with a custom domain of blah.foo.com

Notes:
* Custom domains will error on an invalid SSL certificate since the certificate is self-signed. You will need to upload a signed SSL certificate for your domain to address this.
* The build script will look for the DNS Zone and A records for the custom domain. If either don't exist, it will create the zone and/or associated A records.
* Using the example above, it will be your responsibility to create an NS record from the **foo.com** zone to point to **blah.foo.com**. The nameservers for **blah.foo.com** will be provided by the script during build.
<hr>
<h3> aro-aad-connect.sh</h3>
<hr>
This script will connect Azure Red Hat OpenShift to Azure Active Directory. It will create a new Azure Application & Service Principal within AAD and subsequently configure an OAuth based Authentication Provider to bind to it using the subscription and tenant which are active when the script is run.

The usage is as follows:<br>
<strong>./aro-aad-connect.sh (ARO Cluster Name) (ARO Resource Group Name)<br>
<hr>
<h3>cleanappsp.sh</h3>
<hr>

This script is a housekeeping script that mercilessly deletes all Azure Active Directory applications and service principals with an <strong>aro-</strong> prefix. It is particularly useful when standing up / tearing down multiple ARO clusters.

The usage is as follows:<br>
<strong>./cleanappsp.sh</strong>

<hr>

## Video/Training Series
A video instruction/webinar series will be created on the following ARO topics. If you have additional ideas for content, please contact: stkirk@microsoft.com

* Pre-requisites (registering the ARO extension in the CLI until it GA’s as part of it) and deployment of ARO
* Logging in to the console and demonstrating the difference between public / private clusters
* Connecting Azure Active Directory to ARO 4.3
* Creating an ARO 4.3 project and assigning cluster admin rights to users
* Migration of OpenShift 3.11 / ARO 3.11 projects to ARO 4.3
* Integrating Azure Arc with ARO 4.3

