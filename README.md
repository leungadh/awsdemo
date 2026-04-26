# Juniper vSRX Security Demo on AWS

A self-contained AWS lab demonstrating vSRX NGFW capabilities (Screens, IDP)
against live attacks from a Kali Linux attacker, with a live browser dashboard.

## Architecture

```
Internet
    │
    ▼
  [IGW]
    │
    ├── 10.0.0.0/24  Management subnet ── vSRX fxp0      10.0.0.10  [EIP]
    │                                  ── NAT Gateway               [EIP]
    │
    ├── 10.0.1.0/24  Untrust subnet    ── vSRX ge-0/0/0  10.0.1.254 [EIP]
    │                                  ── Kali            10.0.1.20  [EIP]
    │
    └── 10.0.2.0/24  Trust subnet      ── vSRX ge-0/0/1  10.0.2.254
                                       ── Web Server       10.0.2.100
```

**Attack traffic path:** Kali → vSRX ge-0/0/0 (untrust) → Screen/IDP/Policy → ge-0/0/1 (trust) → Web Server

All Kali→Web traffic is forced through the vSRX via AWS route tables (untrust RT has `10.0.2.0/24 → vSRX untrust ENI`). The web server's internet traffic (for package installs) exits via a NAT gateway in the mgmt subnet.

## Cost

| Resource | Rate |
|---|---|
| vSRX c5.2xlarge + PAYG NGFW license | ~$0.74/hr |
| Kali t3.medium | ~$0.042/hr |
| Web server t3.micro | ~$0.010/hr |
| NAT Gateway | ~$0.045/hr + data transfer |
| **Total** | **~$0.84/hr** |

Run `scripts/down.sh` immediately after your demo to stop billing.

---

## Prerequisites

1. **AWS CLI** configured: `aws configure`

2. **Terraform >= 1.5**: https://developer.hashicorp.com/terraform/install

3. **uv** (for dashboard): https://docs.astral.sh/uv/getting-started/installation/

4. **SSH key pair** — create if needed:
   ```bash
   aws ec2 create-key-pair --key-name awsdemo --query 'KeyMaterial' \
     --output text > ~/.ssh/awsdemo.pem
   chmod 400 ~/.ssh/awsdemo.pem
   ```

5. **Subscribe to AWS Marketplace AMIs** (one-time, free to subscribe):
   - **Juniper vSRX NGFW PAYG**: https://aws.amazon.com/marketplace/pp/prodview-z7jcugjx442hw
   - **Kali Linux** (optional): https://aws.amazon.com/marketplace/pp/prodview-fznsw3f7mq7to

   After subscribing to vSRX, find the AMI ID for your region:
   → Marketplace → Manage subscriptions → vSRX → Continue to Configuration
   → Select region `ap-southeast-1` → note the AMI ID

6. **Configure variables**:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars — set admin_cidr, key_pair_name, vsrx_ami
   ```

---

## Quick Start

```bash
# 1. Bring up all 3 VMs (~5 min)
chmod +x scripts/up.sh scripts/down.sh
./scripts/up.sh

# 2. Apply vSRX config (phase 1 — no IDP)
ssh -i ~/.ssh/awsdemo.pem ec2-user@<vsrx-mgmt-eip>
# Inside vSRX CLI:
configure
# paste contents of vsrx/baseline-phase1.conf
commit and-quit

# 3. Start the dashboard (on your Mac)
cd dashboard
cp config.yaml.example config.yaml
uv run dashboard.py
# Opens http://localhost:8080 automatically

# 4. SSH to Kali and run attacks
ssh -i ~/.ssh/awsdemo.pem ubuntu@<kali-eip>
bash ~/demo/01-port-scan.sh

# 5. Tear down when done
./scripts/down.sh
```

---

## vSRX Configuration

The config is split into two phases. **Phase 1 is required**; Phase 2 needs an IDP-SIG license.

### Phase 1 — Interfaces, Zones, Screens, Policy
```bash
ssh -i ~/.ssh/awsdemo.pem ec2-user@<vsrx-mgmt-eip>
configure
# paste vsrx/baseline-phase1.conf
commit and-quit
```

Verify before proceeding:
```
show interfaces terse              # ge-0/0/0.0 and ge-0/0/1.0 must be up
show security screen ids-option untrust-screen
show security policies
```

### Phase 2 — IDP Policy (requires IDP-SIG license)

**IDP-SIG license is NOT included in the PAYG trial AMI.** Obtain a free 60-day eval from
Juniper's portal, then:

```
# On vSRX:
request system license add terminal
<paste license key>
^D

request security idp security-package download full-update
# Wait ~15-20 min, then:
request security idp security-package install

# Confirm installed:
show security idp status
```

Then apply phase 2:
```bash
configure
# paste vsrx/baseline-phase2.conf
commit and-quit
```

---

## Demo Scenarios

Run from Kali (`ssh -i ~/.ssh/awsdemo.pem ubuntu@<kali-eip>`). Scripts are pre-copied to `~/demo/`.

| Script | Scenario | vSRX Defense | Requires |
|---|---|---|---|
| `01-port-scan.sh` | Port scan (nmap) | Screen: tcp/udp port-scan threshold | Phase 1 |
| `02-syn-flood.sh` | SYN flood (hping3) | Screen: syn-flood SYN proxy | Phase 1 |
| `03-icmp-flood.sh` | ICMP flood + ping-of-death | Screen: icmp flood + large + ping-death | Phase 1 |
| `04-ssh-brute.sh` | SSH brute force (hydra) | IDP: SSH - Critical | Phase 2 + IDP-SIG |
| `05-web-attack.sh` | Web app attacks (nikto, sqlmap) | IDP: HTTP + SQL - Critical | Phase 2 + IDP-SIG |
| `06-ip-spoof.sh` | IP spoofing + malformed TCP | Screen: ip spoofing + land + syn-fin | Phase 1 |

**Demo flow per scenario:**
1. Run the attack script on Kali
2. Watch counters update on the dashboard (http://localhost:8080)
3. On vSRX: `show security screen statistics interface ge-0/0/0` to confirm hits

Scenarios 04 and 05 print a clear "IDP-SIG license required" message and exit if run without Phase 2.

### Useful vSRX verification commands
```
show security screen statistics interface ge-0/0/0
show security policies hit-count from-zone untrust to-zone trust
show security flow session summary
show log security-log | last 30
clear security screen statistics interface ge-0/0/0
```

---

## Live Dashboard

```bash
cd dashboard
uv run dashboard.py    # Opens http://localhost:8080
```

- Polls vSRX via SSH every 15 seconds
- Shows all 3 VM health states (via AWS EC2 API)
- Displays screen counters (port scan, SYN flood, ICMP flood, IP spoofing) live
- **Reset Counters** button clears stats between scenarios

Config: `dashboard/config.yaml` (copy from `config.yaml.example`). `vsrx_public_ip` is auto-detected from `terraform output` if left blank.

---

## File Structure

```
├── terraform/
│   ├── vpc.tf              # VPC, subnets, IGW, NAT GW, route tables
│   ├── security_groups.tf  # 5 security groups
│   ├── instances.tf        # 3 VMs + ENIs + EIPs + ENI-dependent routes
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── user_data/
│       ├── kali.sh         # Installs nmap, hping3, hydra, nikto, sqlmap
│       └── webserver.sh    # Apache + PHP + MySQL + DVWA
│
├── vsrx/
│   ├── baseline-phase1.conf  # Interfaces, zones, screens, policy (no IDP)
│   ├── baseline-phase2.conf  # IDP policy (requires IDP-SIG license)
│   └── README.md
│
├── demo/
│   ├── 01-port-scan.sh
│   ├── 02-syn-flood.sh
│   ├── 03-icmp-flood.sh
│   ├── 04-ssh-brute.sh     # Exits with IDP-required message if no license
│   ├── 05-web-attack.sh    # Exits with IDP-required message if no license
│   ├── 06-ip-spoof.sh
│   └── verify.sh           # vSRX show commands — paste into vSRX CLI
│
├── dashboard/
│   ├── dashboard.py        # Live browser dashboard (uv run dashboard.py)
│   ├── config.yaml.example
│   ├── requirements.txt
│   └── static/
│       └── index.html
│
├── mcp-servers/
│   └── kali-ssh-server.py  # MCP server — lets Claude Code run commands on Kali
│
└── scripts/
    ├── up.sh               # terraform init + plan + apply
    └── down.sh             # confirm + terraform destroy
```
