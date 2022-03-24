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

echo "Current supported Azure Red Hat OpenShift SKUs:"
echo " "
echo "GENERAL PURPOSE"
echo "---------------"
echo "Series	SKU	                vCPU	Memory: GiB"
echo "Dasv4	Standard_D4as_v4	4	16"
echo "Dasv4	Standard_D8as_v4	8	32"
echo "Dasv4	Standard_D16as_v4	16	64"
echo "Dasv4	Standard_D32as_v4	32	128"
echo "Dsv3	Standard_D4s_v3	        4	16"
echo "Dsv3	Standard_D8s_v3	        8	32"
echo "Dsv3	Standard_D16s_v3	16	64"
echo "Dsv3	Standard_D32s_v3	32	128"
echo " "
echo "MEMORY OPTIMIZED"
echo "----------------"
echo "Series	SKU	                vCPU	Memory: GiB"
echo "Esv3	Standard_E4s_v3	        4	32"
echo "Esv3	Standard_E8s_v3	        8	64"
echo "Esv3	Standard_E16s_v3	16	128"
echo "Esv3	Standard_E32s_v3	32	256"
echo " "
echo "COMPUTE OPTIMIZED"
echo "-----------------"
echo "Series	SKU             	vCPU	Memory: GiB"
echo "Fsv2	Standard_F4s_v2	        4	8"
echo "Fsv2	Standard_F8s_v2	        8	16"
echo "Fsv2	Standard_F16s_v2	16	32"
echo "Fsv2	Standard_F32s_v2	32	64"
echo " "
echo "DAY 2 WORKER NODE"
echo "-----------------"
echo "L4s	Standard_L4s		4	32"
echo "L8s	Standard_L8s		8	64"
echo "L16s	Standard_L16s		16	128"
echo "L32s	Standard_L32s		32	256"
echo "L8s_v2	Standard_L8s_v2		8	64"
echo "L16s_v2	Standard_L16s_v2	16	128"
echo "L32s_v2	Standard_L32s_v2	32	256"
echo "L48s_v2	Standard_L48s_v2	32	384"
echo "L64s_v2	Standard_L48s_v2	64	512"

echo " "
echo "#########################################################################################################################################"
echo " "
echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "- PLEASE REFERENCE THE LIST OF SUPPORTED ARO VM SKUs AT: https://docs.microsoft.com/en-us/azure/openshift/support-policies-v4#supported-virtual-machine-sizes -"
echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo " "
echo -n "Enter the Azure VM SKU you wish to use for this machineset:  > "
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
echo -n "replicas t"
sed -i'' -e "s/NUMREPLICAS/$NUMREPLICAS/g" $MACHINESETNAME-template.yaml
echo "Done."
echo " "

echo "Adding new machineset to Azure Red Hat OpenShift cluster $CLUSTERNAME..."
oc apply -f $MACHINESETNAME-template.yaml
echo " "
echo "Script complete."
echo " "

rm -f $MACHINESETNAME-template.yaml

exit 0
