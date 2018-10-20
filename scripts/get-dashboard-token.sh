#!/bin/bash

set -eu

# why so complicated...
kubectl -n kube-system get secrets -o json | \
  jq -r -e --arg user 'admin-user' '.items | map(select(.metadata.name | startswith($user)))[0].data.token' | \
  base64 -d
