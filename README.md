# Azure Red Hat Openshift (ARO) Deployment Code / Scripts
<u>Azure Red Hat OpenShift 3.11</u>

* aro-311-deploy.json
* aro-311-deploy.json.params
```
Text
```
<u>Azure Red Hat OpenShift 4.3</U>

* aro43-build.sh
```
This script will deploy Azure Red Hat OpenShift 4.3 and create the necessary group/network infrastructure required. Until the 'az aro' command becomes GA within the Azure Linux CLI, you must register the extension using the instructions located here:
* https://github.com/Azure/ARO-RP/blob/master/docs/using-az-aro.md
Subsequently, connecting ARO to Azure Active Directory is no longer automated. The process for doing this can be found here:
* https://github.com/jmo808/arm-aro43
```
