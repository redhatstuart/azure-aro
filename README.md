# Azure Red Hat Openshift (ARO) Deployment Code / Scripts

##Azure Red Hat OpenShift 3.11

* aro-311-deploy.json
* aro-311-deploy.json.params

These ARM templates can be used to deploy the latest version of Azure Red Hat OpenShift 3.11. Support for the following has been added based on customer demand:
```
* Peering of Azure vnets / enablement of VPN connectivity / Private clusters
* Integration with Azure Monitoring to provide container application metrics
```
To deploy ARO 3.11 you will need to customize the parameters file per your Azure credentials and execute the following commands using the Azure Linux CLI, or clicking on the link below. The build takes roughly 15-20 minutes.
```
* az group create -n <resourcegroup> -l <azuredatacenter>
* az group deployment create -g <resourcegroup> --template-file aro-311-deploy.json --parameters aro-311-deploy.json.params
```

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjmo808%2farm-aro43%2fmaster%2Fazuredeploy.json" target="_blank">
<img src="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.png"/>
</a>

<hr>

##Azure Red Hat OpenShift 4.3

* aro43-build.sh

This script will deploy Azure Red Hat OpenShift 4.3 and create the necessary group/network infrastructure required. The process takes roughly 35 minutes. Until the 'az aro' command becomes GA within the Azure Linux CLI, you must register the extension using the instructions located here:
```
* https://github.com/Azure/ARO-RP/blob/master/docs/using-az-aro.md
```
Subsequently, connecting ARO to Azure Active Directory is no longer automated. The process for doing this can be found here:
```
* https://github.com/jmo808/arm-aro43
```

<hr>

##Video/Training Series
A video instruction/webinar series will be created on the following ARO topics. If you have additional ideas for content, please contact: stkirk@microsoft.com

* Pre-requisites (registering the ARO extension in the CLI until it GA’s as part of it) and deployment of ARO
* Logging in to the console and demonstrating the difference between public / private clusters
* Connecting Azure Advice Directory to ARO 4.3
* Creating an ARO 4.3 project and assigning cluster admin rights to users
* Migration of OpenShift 3.11 / ARO 3.11 projects to ARO 4.3
* Integrating Azure Arc with ARO 4.3

