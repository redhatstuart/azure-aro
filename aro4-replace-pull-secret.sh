#!/bin/bash

# Written by Stuart Kirk with significant content from Jules Ouellette
# stuart.kirk@microsoft.com, jules.ouellette@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

echo " "
echo "Replacing Azure Red Hat OpenShift Pull Secret"
echo "---------------------------------------------"

if [ $# -ne 1 ]; then
    echo "Usage: $BASH_SOURCE <Current Pull Secret Filename>"
    exit 1
fi

if [ ! -f "$1" ]; then
   echo "$1 does not exist. Please check your filename." 
   exit 1
fi

# We should be logged in now as a cluster admin
if [ "$(oc whoami 2> /dev/null)" != "kube:admin" ]; then
   echo "Please login as kubeadmin."
   exit 1
fi

# Random string generator - don't change this.
RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"
export RAND

# Obtain & decrypt existing pull secret
echo -n "Obtaining & decrypting existing pull secret..."
oc get secret pull-secret -n openshift-config -o json | jq -r '.data.".dockerconfigjson"' | base64 --decode > geneva-$RAND.json
echo "done."

# Merge decrypted pull-secret with RHT pull secret
echo -n "Merging existing ARO pull secret with provided pull secret..."
jq -s '.[0] * .[1]' geneva-$RAND.json $1 | jq -c 'walk(if type == "object" then . | del(."cloud.openshift.com") else . end)' | tr -d "\n\r" > new-pull-secret-import-$RAND.json
echo "done."

# Push to Openshift
echo -n "Uploading revised pull secret to Azure Red Hat OpenShift..."
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=new-pull-secret-import-$RAND.json > /dev/null
echo "done."

# Clean Up
echo -n "Cleaning up..."
rm -f geneva-$RAND.json
rm -f new-pull-secret-import-$RAND.json
echo "done."

exit 0

