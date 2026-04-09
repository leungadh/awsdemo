#!/bin/bash
# Bring up the vSRX demo environment
# Usage: ./scripts/up.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

echo "=============================================="
echo "  Juniper vSRX Security Demo — Bring Up"
echo "=============================================="
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
echo "[*] Checking prerequisites..."

command -v terraform &>/dev/null || {
  echo "[!] terraform not found. Install from: https://developer.hashicorp.com/terraform/install"
  exit 1
}

command -v aws &>/dev/null || {
  echo "[!] aws CLI not found. Install from: https://aws.amazon.com/cli/"
  exit 1
}

aws sts get-caller-identity &>/dev/null || {
  echo "[!] AWS credentials not configured. Run: aws configure"
  exit 1
}

[ -f "${TF_DIR}/terraform.tfvars" ] || {
  echo "[!] terraform/terraform.tfvars not found."
  echo "    Run: cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
  echo "    Then fill in your values (admin_cidr, key_pair_name, vsrx_ami)."
  exit 1
}

echo "[+] Prerequisites OK"
echo ""

# ── Terraform ────────────────────────────────────────────────────────────────
cd "${TF_DIR}"

echo "[*] Initializing Terraform..."
terraform init -upgrade

echo ""
echo "[*] Planning..."
terraform plan -out=tfplan

echo ""
echo "[*] Applying (this takes ~5 minutes)..."
terraform apply tfplan

echo ""
echo "=============================================="
echo "  Demo environment is up!"
echo "=============================================="
echo ""
terraform output
echo ""
echo "Next steps:"
echo "  1. SSH to vSRX and download IDP signatures (~15-20 min):"
echo "     See vsrx/README.md for step-by-step instructions."
echo "  2. Paste vsrx/baseline.conf into the vSRX CLI."
echo "  3. SSH to Kali and run demo scripts in demo/"
echo ""
echo "Cost: ~\$0.79/hr — remember to run scripts/down.sh when done!"
