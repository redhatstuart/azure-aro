#!/bin/bash

# Written by Stuart Kirk with significant content from Jules Ouellette & Ahmed Sabbour
# stuart.kirk@microsoft.com, jules.ouellette@microsoft.com, asabbour@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

echo " "
echo " "
echo "Connecting Azure Red Hat OpenShift to Azure Active Directory"

if [ $# -ne 2 ]; then
    echo "Usage: $BASH_SOURCE <ARO Cluster Name> <ARO Resource Group Name>"
    exit 1
fi

echo "I will attempt to connect Azure Red Hat OpenShift to Azure Active Directory."
echo "*** Please note if your ARO cluster uses a custom domain, the console and app addresses must resolve prior to running this script ***"
echo "ARO Cluster Name: $1"
echo "ARO Resource Group Name: $2"
echo "Shall I continue?" 
PS3="Select a numbered option >> "
options=("Yes" "No")
select yn in "${options[@]}"
do
case $yn in
    Yes ) break ;;
    No ) echo "Well okay then."; exit ;;
esac
done

########## Set Variables
echo -n "Obtaining the variables I need..."
aroName="$1"
export aroName
echo -n "aroName, "
aroRG="$2"
export aroRG
echo -n "aroRG, "
dns="$(az aro show -g $aroRG -n $aroName -o json 2>/dev/null |jq -r '.clusterProfile.resourceGroupId' | cut -f5 -d/ |cut -f2 -d-)"
export dns
echo -n "dns, "
location="$(az aro show -g $aroRG -n $aroName --query location -o tsv  2> /dev/null)"
export location
echo -n "location, "
domain="$(az aro show -g $aroRG -n $aroName -o json 2>/dev/null |jq -r '.clusterProfile.domain')"
export domain
echo -n "domain, "
apiServer="$(az aro show -g $aroRG -n $aroName --query apiserverProfile.url -o tsv  2> /dev/null)"
export apiServer
echo -n "apiServer, "
webConsole="$(az aro show -g $aroRG -n $aroName --query consoleProfile.url -o tsv  2> /dev/null)"
export webConsole
echo -n "webConsole, "
clientSecret="1`cat /dev/urandom | tr -dc 'a-zA-Z0-9@#$%^&*–_!+={}|\?~()]' | fold -w 16 | grep -i '[@#$%^&*–_!+={}|\?~()]' | head -n 1`"
export clientSecret
echo -n "clientSecret, "
consoleUrl=$(az aro show -g $aroRG -n $aroName -o json 2>/dev/null |jq -r '.consoleProfile.url')
export consoleUrl
echo -n "consoleUrl, "
if [ -n "$(echo $consoleUrl | grep aroapp.io)" ]; then
  oauthCallbackURL="https://oauth-openshift.apps.$domain.$location.aroapp.io/oauth2callback/AAD"
  export oauthCallbackURL
else
  oauthCallbackURL="https://oauth-openshift.apps.$dns/oauth2callback/AAD"
  export oauthCallbackURL
fi
echo -n "oauthCallbackURL..."
echo "done."

########## Create Manifest
echo -n "Creating manifest for Azure application..."
cat > manifest.json<< EOF
[{
  "name": "upn",
  "source": null,
  "essential": false,
  "additionalProperties": []
},
{
"name": "email",
  "source": null,
  "essential": false,
  "additionalProperties": []
},
{
  "name": "name",
  "source": null,
  "essential": false,
  "additionalProperties": []
}]
EOF
echo "done."

########## Generate and configure SP
echo -n "Configuring Azure Application & Service Principal..."
appId=$(az ad app create --query appId -o tsv --display-name aro-$domain-aad-connector --reply-urls $oauthCallbackURL --password $clientSecret 2> /dev/null)
tenantId=$(az account show --query tenantId -o tsv 2> /dev/null)
az ad app update --set optionalClaims.idToken=@manifest.json --id $appId
az ad app permission add --api 00000002-0000-0000-c000-000000000000 --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope --id $appId 2> /dev/null
echo "done."

########## Obtain PW and login to ARO CLI
echo -n "Obtaining ARO login credentials for kubeadmin user..."
kubePW=$(az aro list-credentials -n $aroName -g $aroRG -o tsv 2> /dev/null | awk '{print $1}') 
oc login -u kubeadmin -p $kubePW --server $apiServer --insecure-skip-tls-verify=true
echo "done."

########## Create ARO openID authentication secrets file
echo " "
echo "Creating ARO openID authentication secrets file..."
oc create secret generic openid-client-secret-azuread -n openshift-config --from-literal=clientSecret=$clientSecret
echo "done."

########## Create openID authentication provider YAML configuration
echo -n "Extracting current OpenShift authentication provider configuration and merging AAD provider code..."
oc get oauth cluster -o yaml > oidc.yaml
sed -i '$d' oidc.yaml
cat <<EOF >> oidc.yaml
spec:
  identityProviders:
  - name: AAD
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: $appId
      clientSecret: 
        name: openid-client-secret-azuread
      extraScopes: 
      - email
      - profile
      extraAuthorizeParameters: 
        include_granted_scopes: "true"
      claims:
        preferredUsername: 
        - email
        - upn
        name: 
        - name
        email: 
        - email
      issuer: https://login.microsoftonline.com/$tenantId
EOF
echo "done."

########## Apply configuration and force replication
echo " "
echo "Applying revised authentication provider configuration to OpenShift and forcing replication update..."
oc replace -f oidc.yaml
oc create secret generic openid-client-secret-azuread --from-literal=clientSecret=$clientSecret --dry-run -o yaml | oc replace -n openshift-config -f -
echo "done."

########## Clean Up
echo -n "Cleaning up..."
rm -f manifest.json
rm -f oidc.yaml
echo "done."

exit 0

