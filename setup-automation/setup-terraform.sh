#!/bin/bash
echo "change me"

HOSTNAME="tfe-https-${GUID}.${DOMAIN}"

sed -i "/name: \"TFE_HOSTNAME\"/!b;n;s/value: \".*\"/value: \"$HOSTNAME\"/" /etc/containers/systemd/tfe.yaml

podman restart terraform-enterprise-terraform-enterprise
