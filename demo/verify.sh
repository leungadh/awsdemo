#!/bin/bash
# Run on vSRX (ssh root@<vsrx-mgmt-eip>) after each demo scenario
# to verify that the vSRX is detecting and blocking attacks.
#
# Usage: paste these commands directly into the vSRX CLI

cat <<'COMMANDS'
# ── Screen statistics (Scenarios 1, 2, 3, 6) ─────────────────────────────────
show security screen statistics interface ge-0/0/0

# ── Active sessions ───────────────────────────────────────────────────────────
show security flow session
show security flow session summary
show security flow session destination-prefix 10.0.2.100

# ── IDP attack table (Scenarios 4, 5) ────────────────────────────────────────
show security idp attack table
show security idp counters
show security idp counters packet
show security idp status

# ── Policy hit counters ───────────────────────────────────────────────────────
show security policies hit-count from-zone untrust to-zone trust

# ── Security log ─────────────────────────────────────────────────────────────
show log security-log | last 50
show log security-log | match "SCREEN" | last 20
show log security-log | match "IDP" | last 20
show log security-log | match "SSH" | last 20
show log security-log | match "SQL" | last 20

# ── Interface and routing health ──────────────────────────────────────────────
show interfaces ge-0/0/0 terse
show interfaces ge-0/0/1 terse
show route table inet.0

# ── Reset counters between scenarios ─────────────────────────────────────────
# clear security screen statistics
# clear security flow session all
# clear security idp counters
COMMANDS
