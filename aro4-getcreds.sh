#!/bin/bash

# Written by Stuart Kirk
# stuart.kirk@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


################################################################################################## Initialize

echo " "
echo "Display ARO Credentials & Endpoints"
echo "==================================="
echo " "

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

echo "Cluster name: $clusterName"
echo " "

az aro show -n $clusterName -g $clusterResourceGroup -o jsonc --query '[apiserverProfile , consoleProfile , ingressProfiles]'
echo " "
az aro list-credentials -o table -n $clusterName -g $clusterResourceGroup
apiServer="$(az aro show -n aro-stkirk-biahf -g aro-stkirk-biahf-eastus -o tsv --query '[apiserverProfile.url]')"
kubePW="$(az aro list-credentials -n aro-stkirk-biahf -g aro-stkirk-biahf-eastus -o tsv --query '[kubeadminPassword]')"

echo " "
echo "To log in to CLI:"
echo "oc login $apiServer -u kubeadmin -p $kubePW"

echo " "
echo "To delete cluster:"
echo "az aro delete -n $clusterName -g $clusterResourceGroup -y ; az group delete -n $clusterResourceGroup -y"
echo " "

