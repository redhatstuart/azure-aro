#!/bin/bash

# Written by Stuart Kirk
# stuart.kirk@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# API and INGRESS server configuration must be set to either "Public" or "Private" (case sensitive)

# Customize these variables as you need for your cluster deployment
export APIPRIVACY="Public"
export CLUSTER="aro43-`whoami`"
export INGRESSPRIVACY="Public"
export LOCATION="eastus"
export RESOURCEGROUP="$CLUSTER-$LOCATION"
export VNET="10.200.0.0"
export VNET_NAME="aro43-vnet"
export WORKERS="4"

# Don't change these
export VNET_OCTET1="`echo $VNET | cut -f1 -d.`"
export VNET_OCTET2="`echo $VNET | cut -f2 -d.`"

echo " "
echo "Building Azure Red Hat OpenShift 4.3"
echo "------------------------------------"

# Resource Group
echo "Creating Resource Group"
az group create -g "$RESOURCEGROUP" -l $LOCATION --tags "ARO 4.3 created `date +%Y%m%d`" >> /dev/null 2>&1 

# VNet Creation
echo "Creating Virtual Network"
az network vnet create -g "$RESOURCEGROUP" -n $VNET_NAME --address-prefixes $VNET/16 > /dev/null 2>&1

# Subnet Creation
echo "Creating 'Master' Subnet"
az network vnet subnet create -g "$RESOURCEGROUP" --vnet-name $VNET_NAME -n "$CLUSTER-master" --address-prefixes "$VNET_OCTET1.$VNET_OCTET2.`shuf -i 0-254 -n 1`.0/24" --service-endpoints Microsoft.ContainerRegistry > /dev/null 2>&1
echo "Creating 'Worker' Subnet"
az network vnet subnet create -g "$RESOURCEGROUP" --vnet-name $VNET_NAME -n "$CLUSTER-worker" --address-prefixes "$VNET_OCTET1.$VNET_OCTET2.`shuf -i 0-254 -n 1`.0/24" --service-endpoints Microsoft.ContainerRegistry > /dev/null 2>&1
echo "Disabling 'PrivateLinkServiceNetworkPolicies' in 'Master' Subnet"
az network vnet subnet update -g "$RESOURCEGROUP" --vnet-name $VNET_NAME -n "$CLUSTER-master" --disable-private-link-service-network-policies true > /dev/null 2>&1

# Build ARO
echo "Building Azure Red Hat OpenShift 4.3 - this takes roughly 30 minutes"
time az aro create -g "$RESOURCEGROUP" -n "$CLUSTER" --vnet "$VNET_NAME" --master-subnet "$CLUSTER-master" --worker-subnet "$CLUSTER-worker" --ingress-visibility "$INGRESSPRIVACY" --apiserver-visibility "$APIPRIVACY" --worker-count "$WORKERS" --tags "ARO 4.3 created `date +%Y%m%d`" 2>/dev/null

# Output Messages

echo " "
echo "`az aro list-credentials -n $CLUSTER -g $RESOURCEGROUP 2>/dev/null`"

echo " "
echo "$APIPRIVACY Console URL"
echo "-------------------"
echo "`az aro show -n aro43-stkirk -g aro43-stkirk-eastus -o json 2>/dev/null |jq -r '.consoleProfile.url'`"

echo " "
echo "Procedure for connecting ARO to AAD"
echo "-----------------------------------"
echo "https://github.com/jmo808/arm-aro43"

echo " " 
echo "Redirect URI to enter into AAD Service Principal"
echo "------------------------------------------------"
export DOMAIN="`az aro show -n $CLUSTER -g $RESOURCEGROUP -o json 2>/dev/null |jq -r '.clusterProfile.domain'`"
echo "https://oauth-openshift.apps.$DOMAIN.$LOCATION.aroapp.io/oauth2callback/AAD"

echo " "
echo "Delete the ARO Cluster"
echo "----------------------"
echo "az aro delete -n $CLUSTER -g $RESOURCEGROUP -y ; az group delete -n $RESOURCEGROUP -y"

echo " "
echo "-end-"
echo " "
exit 0
