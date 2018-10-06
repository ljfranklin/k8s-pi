#!/bin/bash

set -eu

ansible-playbook \
  --private-key ~/.ssh/id_rsa_k8s \
  --extra-vars @secrets.yml \
  bootstrap.yml

echo "Download the config to run kubectl:"
echo "scp k8s@k8s-master.local:/home/k8s/.kube/config ~/.kube/"
