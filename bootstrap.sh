#!/bin/bash

set -eu

my_dir="$( cd "$( dirname "$0" )" && pwd )"
tmpdir="$(mktemp -d /tmp/k8s-pi.XXXXXXXX)"
trap '{ rm -rf "${tmpdir}"; }' EXIT

: "${WORKER_COUNT:=5}"
: "${PRIVATE_KEY_PATH:="$HOME/.ssh/id_rsa_k8s"}"
: "${SECRETS_PATH:="${my_dir}/secrets/secrets.yml"}"

cat << EOF > "${tmpdir}/inventory"
[master]
k8s-master.local

[workers]
EOF

for i in $(seq 1 "${WORKER_COUNT}"); do
  echo "k8s-worker${i}.local" >> "${tmpdir}/inventory"
done

ansible-playbook \
  --private-key "${PRIVATE_KEY_PATH}" \
  -i "${tmpdir}/inventory" \
  --extra-vars "@${SECRETS_PATH}" \
  "${my_dir}/bootstrap.yml"

echo ""
echo "Install kubectl CLI:"
echo "https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl"

echo ""
echo "Download the config to run kubectl:"
echo "scp k8s@k8s-master.local:/home/k8s/.kube/config ~/.kube/"

echo ""
echo "Install helm CLI:"
echo "https://docs.helm.sh/using_helm/#installing-helm"
