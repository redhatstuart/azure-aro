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
echo -n "Inserting new secret into existing Azure Service Principal..."
az ad sp credential reset -n $SPAPPID --credential-description "$(date +%m%d%Y%H%M%S)" --end-date "2299-12-31" -p $NEWSPSECRET > /dev/null 2>&1
echo "Done."
echo -n "Encoding new secret for insertion into Azure Red Hat OpenShift..."
NEWSPSECRETENCODED="$(echo -n $NEWSPSECRET | base64 | tr -d '\n\r')"
echo "Done."
echo -n "Patching existing Azure Red Hat OpenShift secrets..."
oc patch secret azure-credentials -n kube-system -p="{\"data\":{\"azure_client_secret\": \"$NEWSPSECRETENCODED\"}}" > /dev/null 2>&1
oc patch secret azure-cloud-credentials -n openshift-machine-api -p="{\"data\":{\"azure_client_secret\": \"$NEWSPSECRETENCODED\"}}" > /dev/null 2>&1
oc patch secret cloud-credentials -n openshift-ingress-operator -p="{\"data\":{\"azure_client_secret\": \"$NEWSPSECRETENCODED\"}}" > /dev/null 2>&1
oc patch secret installer-cloud-credentials -n openshift-image-registry -p="{\"data\":{\"azure_client_secret\": \"$NEWSPSECRETENCODED\"}}" > /dev/null 2>&1
echo "Done."
echo -n "Sleeping for 5 minutes to allow credentials to propogate (do NOT attempt any MachineSet scaling during this time)..."
sleep 360
echo "Done."
echo " "

exit 0
