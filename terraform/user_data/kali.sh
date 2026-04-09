#!/bin/bash
# Attacker VM cloud-init: install attack tools on Ubuntu 22.04
# All tools are available via apt — no Kali Linux AMI required.
# SSH user: ubuntu (not kali)
# Runs automatically on first boot (~2-3 minutes)

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  nmap \
  hping3 \
  hydra \
  nikto \
  sqlmap \
  curl \
  wget \
  net-tools \
  iputils-ping

echo "Kali tool install complete" >> /var/log/demo-setup.log
