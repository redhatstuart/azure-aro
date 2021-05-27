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

echo " "
echo "Rotate Azure Red Hat OpenShift Service Principal Credentials"
echo "============================================================"

if [ $# -ne 1 ]; then
    echo "Usage: $BASH_SOURCE <name of cluster>"
    exit 1
fi

if [ -z "$(az aro list -o table |grep -i  $1)" ]; then
    echo "$1 doesn't seem to exist. Review the output of 'az aro list'"
    exit 1
fi

clusterName="$(az aro list -o table |grep -i $1 | awk '{print $1}')"
clusterResourceGroup="$(az aro list -o table |grep -i $1 | awk '{print $2}')"

# We should be logged in as a cluster admin
if [ "$(oc whoami)" != "kube:admin" ]; then
   echo "Please log in to your Azure Red Hat OpenShift cluster as the kubeadmin user."
   exit 1
fi

echo -n "Obtaining Azure Service Principal AppID for existing cluster..."
SPAPPID="$(oc get secret azure-credentials -n kube-system -o json | jq -r .data.azure_client_id | base64 --decode)"
echo "Done."
echo -n "Obtaining Azure Service Principal credential information..."
CREATED="$(az ad sp credential list --id $SPAPPID --query '[].startDate' -o tsv)"
EXPIRING="$(az ad sp credential list --id $SPAPPID --query '[].endDate' -o tsv)"
echo "Done."

echo " "
echo "Based on your current Azure Red Hat OpenShift AAD Application ID, $SPAPPID, the dates for your current credential are as follows:"
echo "Create date: $CREATED"
echo "Expiration date: $EXPIRING"
echo " "
echo "Shall I continue? (you must be logged in as a cluster administrator with 'oc')"
PS3="Select a numbered option >> "
options=("Yes" "No")
select yn in "${options[@]}"
do
case $yn in
    Yes ) break ;;
    No ) echo "Well okay, then."; exit ;;
esac
done

while [[ "$valid" -lt 1 || "$valid" -gt 250 ]]
do

  echo -n "How many years would you like the new service principal key to be valid for from today's date (1-250) >> "
  read valid

done

expiry="$(date -d "+$valid years" +%Y-%m-%d)"
echo " "

echo "***********************************************"
echo "* The new expiration date will be: $expiry *"
echo "* Sleeping for 10 seconds. CTL-C to abort.    *"
echo "***********************************************"
sleep 10

echo " "
echo -n "Obtaining Azure Service Principal KeyID..."
SPSECRETKEYID="$(az ad sp credential list --id $SPAPPID -o tsv | awk '{print $4}')"
echo "Done."
echo -n "Deleting existing Azure Service Principal Secret..."
az ad sp credential delete --id $SPAPPID --key-id $SPSECRETKEYID
echo "Done."
echo -n "Generating new Azure Service Principal Secret..."
NEWSPSECRET="$(cat /proc/sys/kernel/random/uuid | tr -d '\n\r')"
echo "Done."
echo -n "Inserting new secret $NEWSPSECRET into existing Azure Service Principal..."
az ad sp credential reset -n $SPAPPID --credential-description "$(date +%m%d%Y%H%M%S)" --end-date "$expiry" -p $NEWSPSECRET > /dev/null 2>&1
echo "Done."
echo "Calling the Azure Linux CLI to push the new secret $NEWSPSECRET into Azure Red Hat OpenShift"
az aro update -n $clusterName -g $clusterResourceGroup --client-id $SPAPPID --client-secret $NEWSPSECRET

echo " "
echo "Please remember that if you are using the same service principal to connect to Azure Active Directory you will need to"
echo "update the OpenShift secret for the AAD OAuth connector which is typically 'openid-client-secret-azuread' per Microsoft"
echo "documentation. Given that every use case is different (using the same SP vs an SP specific for AAD connectivity)"
echo "this script will not address the patching of AAD secrets."
echo " "
echo "Done."
echo " "

exit 0
