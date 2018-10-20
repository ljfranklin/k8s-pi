#!/bin/bash

set -eu -o pipefail


: "${CLOUDFLARE_EMAIL:?}"
: "${CLOUDFLARE_API_TOKEN:?}"

zone="$1"
domain="$2"

echo "Updating DNS for '${domain}'..."

cat << EOF > /tmp/ddclient.conf
ssl=yes
use=web
protocol=cloudflare, \
zone=${zone}, \
ttl=120, \
login=${CLOUDFLARE_EMAIL}, \
password=${CLOUDFLARE_API_TOKEN} \
${domain}
EOF
chmod 600 /tmp/ddclient.conf

ddclient -debug -file /tmp/ddclient.conf

echo "Success!"
