#!/bin/bash

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <EXTERNAL_VPN_HOSTNAME>"
  exit
fi

hostname="$1"

key_path="secrets/k8s.ovpn"
mkdir -p secrets

if [ -f "${key_path}" ]; then
  echo "VPN config already exists at '${key_path}'. Delete it and try again."
  exit 1
fi

pod_name=$(kubectl get pods -l "app=openvpn" -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "${pod_name}" /etc/openvpn/setup/newClientCert.sh "k8s" "${hostname}"
kubectl exec -it "${pod_name}" cat "/etc/openvpn/certs/pki/k8s.ovpn" > "${key_path}"

echo "Wrote VPN config to '${key_path}'"
