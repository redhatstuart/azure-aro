#!/bin/bash -e

# Written by Stuart Kirk
# stuart.kirk@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# API and INGRESS server configuration must be set to either "Public" or "Private" (case sensitive)


################################################################################################## Initialize


if [ $# -gt 1 ]; then
    echo "Usage: $BASH_SOURCE <Custom Domain eg. aro.foo.com>"
    exit 1
fi

# Random string generator - don't change this.
RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"
export RAND

# Customize these variables as you need for your cluster deployment
APIPRIVACY="Public"
export APIPRIVACY
INGRESSPRIVACY="Public"
export INGRESSPRIVACY
LOCATION="eastus"
export LOCATION
VNET="10.151.0.0"
export VNET
WORKERS="4"
export WORKERS

# Don't change these
BUILDDATE="$(date +%Y%m%d-%H%M%S)"
export BUILDDATE
CLUSTER="aro-$(whoami)-$RAND"
export CLUSTER
RESOURCEGROUP="$CLUSTER-$LOCATION"
export RESOURCEGROUP
SUBID="$(az account show -o json |jq -r '.id')"
export SUBID
VNET_NAME="$CLUSTER-vnet"
export VNET_NAME
VNET_OCTET1="$(echo $VNET | cut -f1 -d.)"
export VNET_OCTET1
VNET_OCTET2="$(echo $VNET | cut -f2 -d.)"
export VNET_OCTET2


################################################################################################## Infrastructure Provision


echo " "
echo "Building Azure Red Hat OpenShift"
echo "--------------------------------"

if [ $# -eq 1 ]; then
    DNS="--domain=$1"
    export DNS
    echo "You have specified a parameter for a custom domain: $1. I will configure ARO to use this domain."
    echo " "
fi

# Resource Group Creation
echo -n "Creating Resource Group..."
az group create -g "$RESOURCEGROUP" -l "$LOCATION" >> /dev/null 
echo "done"

# VNet Creation
echo -n "Creating Virtual Network..."
az network vnet create -g "$RESOURCEGROUP" -n $VNET_NAME --address-prefixes $VNET/16 > /dev/null
echo "done"

# Subnet Creation
echo -n "Creating 'Master' Subnet..."
az network vnet subnet create -g "$RESOURCEGROUP" --vnet-name $VNET_NAME -n "$CLUSTER-master" --address-prefixes "$VNET_OCTET1.$VNET_OCTET2.$(shuf -i 0-254 -n 1).0/24" --service-endpoints Microsoft.ContainerRegistry > /dev/null
echo "done"
echo -n "Creating 'Worker' Subnet..."
az network vnet subnet create -g "$RESOURCEGROUP" --vnet-name $VNET_NAME -n "$CLUSTER-worker" --address-prefixes "$VNET_OCTET1.$VNET_OCTET2.$(shuf -i 0-254 -n 1).0/24" --service-endpoints Microsoft.ContainerRegistry > /dev/null
echo "done"

# VNet & Subnet Configuration
echo -n "Disabling 'PrivateLinkServiceNetworkPolicies' in 'Master' Subnet..."
az network vnet subnet update -g "$RESOURCEGROUP" --vnet-name $VNET_NAME -n "$CLUSTER-master" --disable-private-link-service-network-policies true > /dev/null
echo "done"
echo -n "Adding ARO RP Contributor access to VNET..."
az role assignment create --scope /subscriptions/$SUBID/resourceGroups/$RESOURCEGROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME --assignee f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875 --role "Contributor" > /dev/null
echo "done"

# Pull Secret
echo -n "Checking if pull-secret.txt exists..."
if [ -f "pull-secret.txt" ]; then
    echo "detected"
    echo -n "Removing extra characters from pull-secret.txt..."
    tr -d "\n\r" < pull-secret.txt >pull-secret.tmp
    rm -f pull-secret.txt
    mv pull-secret.tmp pull-secret.txt
    echo "done"
    PULLSECRET="--pull-secret=$(cat pull-secret.txt)"
    export PULLSECRET
else
    echo "not detected."
fi
echo " "

################################################################################################## Build ARO


# Build ARO
echo "==============================================================================================================================================================="
echo "Building Azure Red Hat OpenShift - this takes roughly 30-40 minutes. The time is now: $(date)..."
echo " "
echo "Executing: "
echo "az aro create -g $RESOURCEGROUP -n $CLUSTER --vnet=$VNET_NAME --master-subnet=$CLUSTER-master --worker-subnet=$CLUSTER-worker --ingress-visibility=$INGRESSPRIVACY --apiserver-visibility=$APIPRIVACY --worker-count=$WORKERS $DNS $PULLSECRET"
echo " "
time az aro create -g "$RESOURCEGROUP" -n "$CLUSTER" --vnet="$VNET_NAME" --master-subnet="$CLUSTER-master" --worker-subnet="$CLUSTER-worker" --ingress-visibility="$INGRESSPRIVACY" --apiserver-visibility="$APIPRIVACY" --worker-count="$WORKERS" $DNS $PULLSECRET


################################################################################################## Post Provisioning


# Update ARO RG tags
echo " "
echo -n "Updating resource group tags..."
DOMAIN="$(az aro show -n $CLUSTER -g $RESOURCEGROUP -o json 2>/dev/null |jq -r '.clusterProfile.resourceGroupId' | cut -f5 -d/ |cut -f2 -d-)"
export DOMAIN
VERSION="$(az aro show -n $CLUSTER -g $RESOURCEGROUP -o json 2>/dev/null |jq -r '.clusterProfile.version')"
export VERSION
az group update -g "aro-$DOMAIN" --tags "ARO $VERSION Build Date=$BUILDDATE" >> /dev/null 2>&1
az group update -g "$RESOURCEGROUP" --tags "ARO $VERSION Build Date=$BUILDDATE" >> /dev/null 2>&1
echo "done."

# Forward Zone Creation (if necessary)
if [ -n "$DNS" ]; then
    DNS="$(echo $DNS | cut -f2 -d=)"
    export DNS
    if [ -z "$(az network dns zone list -o json | jq -r '.[] | .name' | grep $DNS)" ]; then
        echo -n "Zone $DNS not detected. Creating..."
	az network dns zone create -n $DNS -g $RESOURCEGROUP >> /dev/null 2>&1
        echo "done." 
        echo " "
        echo "Dumping nameservers for newly created zone..." 
        az network dns zone show -g $RESOURCEGROUP -n $DNS -o json | jq -r '.nameServers[]'
        echo " "
    fi
    if [ -z "$(az network dns record-set list -g $RESOURCEGROUP -z $DNS |grep api)" ]; then
        echo -n "An A record for the ARO API does not exist. Creating..." 
        IPAPI="$(az aro show -n $CLUSTER -g $RESOURCEGROUP -o json 2>/dev/null | jq -r '.apiserverProfile.ip')"
	export IPAPI
	az network dns record-set a add-record -z $DNS -g $RESOURCEGROUP -a $IPAPI -n api >> /dev/null 2>&1
        echo "done."
    fi
    if [ -z "$(az network dns record-set list -g $RESOURCEGROUP -z $DNS |grep apps)" ]; then
        echo -n "A wildcard A record for ARO applications does not exist. Creating..."
        IPAPPS="$(az aro show -n $CLUSTER -g $RESOURCEGROUP -o json 2>/dev/null | jq -r '.ingressProfiles[0] .ip')"
	export IPAPPS
        az network dns record-set a add-record -z $DNS -g $RESOURCEGROUP -a $IPAPPS -n *.apps >> /dev/null 2>&1
        echo "done."
    fi
fi


################################################################################################## Output Messages


echo " "
echo "$(az aro list-credentials -n $CLUSTER -g $RESOURCEGROUP 2>/dev/null)"

echo " "
echo "$APIPRIVACY Console URL"
echo "-------------------"
echo "$(az aro show -n $CLUSTER -g $RESOURCEGROUP -o json 2>/dev/null |jq -r '.consoleProfile.url')"

echo " "
echo "To delete this ARO Cluster"
echo "--------------------------"
echo "az aro delete -n $CLUSTER -g $RESOURCEGROUP -y ; az group delete -n $RESOURCEGROUP -y"

echo " "
echo "-end-"
echo " "
exit 0
