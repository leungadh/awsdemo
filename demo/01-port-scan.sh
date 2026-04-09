#!/bin/bash
# Scenario 1: Port Scan with nmap
# Run this from Kali Linux (ssh kali@<kali-eip>)
#
# BEFORE applying defense:
#   nmap completes quickly and shows open ports (80, 443, 22)
#
# AFTER defense (Screen: tcp port-scan threshold 5000):
#   nmap sees all ports as filtered/dropped; scan hangs or shows no open ports
#
# Verify on vSRX:
#   show security screen statistics interface ge-0/0/0
#   show log security-log | match "PORT-SCAN" | last 20

TARGET="10.0.2.100"

echo "========================================"
echo "Scenario 1: Port Scan"
echo "Target: $TARGET"
echo "========================================"
echo ""

echo "[*] Quick TCP SYN scan — top 1000 ports"
nmap -sS -T4 "$TARGET"
echo ""

echo "[*] Full port range scan with version detection"
nmap -sS -sV -p 1-65535 --min-rate 5000 "$TARGET"
echo ""

echo "[*] OS detection + script scan"
sudo nmap -A -T4 "$TARGET"
echo ""

echo "[+] Scan complete. On vSRX, run:"
echo "    show security screen statistics interface ge-0/0/0"
