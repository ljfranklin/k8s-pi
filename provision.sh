#!/bin/bash

set -eu

my_dir="$( cd "$( dirname "$0" )" && pwd )"

playbook="" # required
ip_range_start="192.168.1.100"
k8s_version="v1.12.3"
private_key_path="$HOME/.ssh/id_rsa_k8s"
secrets_path="${my_dir}/secrets/secrets.yml"
worker_count="5"

# Colors
red='\033[0;31m'
green='\033[0;92m'
nc='\033[0m'

usage() {
  >&2 cat <<EOF

Run the given playbook against K8S cluster

Usage:
  $0 <options>

Options:
  -b <playbook>     (required) Run the given playbook: 'bootstrap', 'upgrade', or 'deploy'
  -i <start_ip>     (optional) The IP of the first machine to provision, default: '${ip_range_start}'
                               Note: script assumes all machines are given sequential IP addresses
  -p <key_path>     (optional) Path to SSH key, default: '${private_key_path}'
  -s <secret_path>  (optional) Path to secrets file, default: '${secrets_path}'
  -t <version>      (optional) Target k8s version to install, default: '${k8s_version}'
  -w <worker_count> (optional) Number of worker machines, default: '${worker_count}'
  -h                (optional) Show this help text
EOF
}

while getopts 'b:i:p:s:w:h' flag; do
  case "${flag}" in
    b)
      playbook="${OPTARG}"
      ;;
    i)
      ip_range_start="${OPTARG}"
      ;;
    p)
      private_key_path="${OPTARG}"
      ;;
    s)
      secrets_path="${OPTARG}"
      ;;
    t)
      k8s_version="${OPTARG}"
      ;;
    w)
      worker_count="${OPTARG}"
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [ -z "${playbook}" ]; then
  >&2 echo -e "${red}Missing require '-b' argument${nc}"
  usage
  exit 1
fi
if ! ls "${my_dir}/playbooks/${playbook}.yml" &> /dev/null; then
  >&2 echo -e "${red}Unknown argument to '-b': ${playbook}${nc}"
  usage
  exit 1
fi

tmpdir="$(mktemp -d /tmp/k8s-pi.XXXXXXXX)"
trap '{ rm -rf "${tmpdir}"; }' EXIT

cat << EOF > "${tmpdir}/inventory"
[master]
${ip_range_start}

[workers]
EOF

for i in $(seq 1 "${worker_count}"); do
  subnet="$(cut -d '.' -f1-3 <<< "${ip_range_start}")"
  start_ip="$(cut -d '.' -f4 <<< "${ip_range_start}")"
  echo "${subnet}.$((start_ip+i))" >> "${tmpdir}/inventory"
done

pushd "${my_dir}" > /dev/null
  ansible-playbook \
    --private-key "${private_key_path}" \
    -i "${tmpdir}/inventory" \
    --extra-vars "@${secrets_path}" \
    --extra-vars "k8s_version=${k8s_version}" \
    "${my_dir}/playbooks/${playbook}.yml"
popd > /dev/null

echo ""
echo -e "${green}Success!${nc}"

echo ""
echo "Install kubectl CLI:"
echo "https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl"

echo ""
echo "Download the config to run kubectl:"
echo "scp k8s@${ip_range_start}:/home/k8s/.kube/config ~/.kube/"

echo ""
echo "Install helm CLI:"
echo "https://docs.helm.sh/using_helm/#installing-helm"
