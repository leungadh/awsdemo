#!/bin/bash
# Tear down the vSRX demo environment
# Usage: ./scripts/down.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

echo "=============================================="
echo "  Juniper vSRX Security Demo — Teardown"
echo "=============================================="
echo ""
echo "WARNING: This will DESTROY all demo resources:"
echo "  - vSRX instance (c5.2xlarge)"
echo "  - Kali Linux instance (t3.medium)"
echo "  - Web server instance (t3.micro)"
echo "  - VPC, subnets, route tables, security groups"
echo "  - 2 Elastic IPs"
echo ""
read -rp "Type 'yes' to confirm teardown: " confirm

if [ "${confirm}" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

cd "${TF_DIR}"

echo ""
echo "[*] Destroying all resources..."
terraform destroy -auto-approve

echo ""
echo "=============================================="
echo "  All demo resources destroyed."
echo "  Billing has stopped for EC2 instances."
echo "=============================================="
