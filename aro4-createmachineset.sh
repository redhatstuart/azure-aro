#!/bin/bash

# Written by Stuart Kirk
# stuart.kirk@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

##################################################################################################

# Make sure you also download machineset-template.yaml and have it in the same directory this script is executed in.

# exit when any command fails
set -e

# Begin
echo " "
echo "Adding machineset to Azure Red Hat OpenShift"
echo "--------------------------------------------"
echo "You must be logged in to your Azure Red Hat OpenShift cluster (oc) as a cluster-admin and into the Azure Linux CLI (az) in the subscription of your ARO cluster"
echo " "

if [ ! -f "machineset-template.yaml" ]; then
    echo "Please also obtain the machine-template.yaml file and place it in the same directory in which you are invoking this script."
    exit 1
fi

echo -n "Determining the name of an existing machineset..."
CURRENTMACHINESET="$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')"
echo "Done."

echo -n "Obtaining required variables..."
echo -n "azure region, "
AZUREDC="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.location}')"
echo -n "marketplace sku, "
AROSKU="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.image.sku}')"
echo -n "marketplace version, "
AROSKUVERSION="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.image.version}')"
echo -n "cluster name, "
CLUSTERNAME="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.metadata.labels.machine\.openshift\.io/cluster-api-cluster}')"
echo -n "network rg, "
NETWORKRG="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.networkResourceGroup}')"
echo -n "cluster rg, "
PROTECTEDRG="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.resourceGroup}')"
echo -n "lb name, "
PUBLICLBNAME="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.publicLoadBalancer}')"
echo -n "worker subnet, "
SUBNET="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.subnet}')"
echo -n "vnet name "
VNETNAME="$(oc get machineset $CURRENTMACHINESET -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.vnet}')"
echo "Done."

echo " "
echo "Your existing machinesets:"
echo " "
oc get machineset -n openshift-machine-api -o wide

echo " "
echo "#########################################################################################################################################"
echo " "

echo -n "Enter the name of the machineset you wish to create (some format of what you see above):  > "
read MACHINESETNAME
echo -n "Enter the Azure Availability Zone this machineset should create nodes in (1, 2 or 3):  > "
read WHICHAZ
echo -n "Enter the number of worker nodes that should be created for this machineset: > "
read NUMREPLICAS

echo -n "Making a copy of the existing machineset template..."
cp machineset-template.yaml $MACHINESETNAME-template.yaml
echo "Done."

echo " "
echo "#########################################################################################################################################"
echo " "
echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "- PLEASE REFERENCE THE LIST OF SUPPORTED ARO VM SKUs AT: https://docs.microsoft.com/en-us/azure/openshift/support-policies-v4#supported-virtual-machine-sizes -"
echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo " "
echo "Keep in mind that not all VM SKUs are avaialble in all Azure regions"
echo -n "Enter the Azure VM SKU you wish to use for this machineset (ex: Standard_E4s_v3):  > "
read VMSKU
echo " "

if [ -z "$(az vm list-sizes -l $AZUREDC -o tsv |grep $VMSKU)" ]; then
	echo "You entered an invalid Azure VM SKU. Please try again."
	exit 1
fi

echo -n "Making a copy of the existing machineset template..."
cp machineset-template.yaml $MACHINESETNAME-template.yaml
echo "Done."

MEMORYMB="$(az vm list-sizes -l $AZUREDC -o tsv |grep $VMSKU | awk '{print $2}')"
VCPUCORES="$(az vm list-sizes -l $AZUREDC -o tsv |grep $VMSKU | awk '{print $4}')"

echo -n "Performing variable substitutions..."
echo -n "memory, "
sed -i'' -e "s/MEMORYMB/$MEMORYMB/g" $MACHINESETNAME-template.yaml
echo -n "cores, "
sed -i'' -e "s/VCPUCORES/$VCPUCORES/g" $MACHINESETNAME-template.yaml
echo -n "cluster name, "
sed -i'' -e "s/CLUSTERNAME/$CLUSTERNAME/g" $MACHINESETNAME-template.yaml
echo -n "machineset name, "
sed -i'' -e "s/MACHINESETNAME/$MACHINESETNAME/g" $MACHINESETNAME-template.yaml
echo -n "network rg, "
sed -i'' -e "s/NETWORKRG/$NETWORKRG/g" $MACHINESETNAME-template.yaml
echo -n "lb name, "
sed -i'' -e "s/PUBLICLBNAME/$PUBLICLBNAME/g" $MACHINESETNAME-template.yaml
echo -n "vnet name, "
sed -i'' -e "s/VNETNAME/$VNETNAME/g" $MACHINESETNAME-template.yaml
echo -n "availability zone, "
sed -i'' -e "s/WHICHAZ/$WHICHAZ/g" $MACHINESETNAME-template.yaml
echo -n "cluster rg, "
sed -i'' -e "s/PROTECTEDRG/$PROTECTEDRG/g" $MACHINESETNAME-template.yaml
echo -n "azure region, "
sed -i'' -e "s/AZUREDC/$AZUREDC/g" $MACHINESETNAME-template.yaml
echo -n "vm sku, "
sed -i'' -e "s/VMSKU/$VMSKU/g" $MACHINESETNAME-template.yaml
echo -n "marketplace version, "
sed -i'' -e "s/AROSKUVERSION/$AROSKUVERSION/g" $MACHINESETNAME-template.yaml
echo -n "marketplace sku, "
sed -i'' -e "s/AROSKU/$AROSKU/g" $MACHINESETNAME-template.yaml
echo -n "worker subnet, "
sed -i'' -e "s/SUBNET/$SUBNET/g" $MACHINESETNAME-template.yaml
echo -n "replicas, "
sed -i'' -e "s/NUMREPLICAS/$NUMREPLICAS/g" $MACHINESETNAME-template.yaml
echo "Done."
echo " "

echo -n "Adding new machineset to Azure Red Hat OpenShift cluster $CLUSTERNAME..."
oc apply -f $MACHINESETNAME-template.yaml
echo " "
echo "Script complete."
echo " "

rm -f $MACHINESETNAME-template.yaml

exit 0
