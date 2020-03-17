#!/bin/bash

# Written by Stuart Kirk
# stuart.kirk@microsoft.com
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

for i in `az ad app list --show-mine -o json | jq -r ".[] | .displayName" |grep "aro-"`; do az ad app list --display-name $i -o json | jq -r ".[] | .objectId"; done > appids

for i in `cat appids`; do
  echo "Erasing appid: $i"
  az ad app delete --id $i
done

for j in `az ad sp list --show-mine -o json | jq -r ".[] | .displayName" |grep "aro-"`; do az ad sp list --display-name $i -o json | jq -r ".[] | .objectId"; done > spids

for j in `cat spids`; do
  echo "Errasing sp: $j"
  az ad sp delete --id $j
done

rm -f appids
rm -f spids

