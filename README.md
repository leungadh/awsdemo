# Juniper vSRX Security Demo on AWS

A self-contained AWS lab demonstrating vSRX NGFW capabilities (Screens, IDP)
against live attacks from a Kali Linux attacker.

## Architecture

```
Internet
    │
    ▼
  [IGW]
    │
    ├── 10.0.0.0/24  Management subnet ── vSRX fxp0  10.0.0.10  [EIP]
    │
    ├── 10.0.1.0/24  Untrust subnet    ── vSRX ge-0/0/0  10.0.1.254
    │                                  ── Kali           10.0.1.20  [EIP]
    │
    └── 10.0.2.0/24  Trust subnet      ── vSRX ge-0/0/1  10.0.2.254
                                       ── Web Server      10.0.2.100
```

**Traffic path:** Kali → SRX ge-0/0/0 (untrust) → policy/IDP/Screen → ge-0/0/1 (trust) → Web Server

All Kali→Web traffic is forced through the vSRX via AWS route tables. The web server has
no direct internet route. Security enforcement happens at the vSRX.

## Cost

| Resource | Rate |
|---|---|
| vSRX c5.2xlarge + PAYG NGFW license | ~$0.74/hr |
| Kali t3.medium | ~$0.042/hr |
| Web server t3.micro | ~$0.010/hr |
| **Total** | **~$0.79/hr** |

Run `scripts/down.sh` immediately after your demo to stop billing.

---

## Prerequisites

1. **AWS CLI** configured: `aws configure`

2. **Terraform >= 1.5**: https://developer.hashicorp.com/terraform/install

3. **SSH key pair** — create if needed:
   ```bash
   aws ec2 create-key-pair --key-name awsdemo --query 'KeyMaterial' \
     --output text > ~/.ssh/awsdemo.pem
   chmod 400 ~/.ssh/awsdemo.pem
   ```

4. **Subscribe to AWS Marketplace AMIs** (one-time, free to subscribe):
   - **Juniper vSRX NGFW PAYG**: https://aws.amazon.com/marketplace/pp/prodview-z7jcugjx442hw
   - **Kali Linux**: https://aws.amazon.com/marketplace/pp/prodview-fznsw3f7mq7to

   After subscribing to vSRX, find the AMI ID:
   → Marketplace → Manage subscriptions → vSRX → Continue to Configuration
   → Select region `ap-southeast-1` → note the AMI ID

5. **Configure variables**:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

---

## Quick Start

```bash
# Bring up everything (~5 min)
chmod +x scripts/up.sh scripts/down.sh
./scripts/up.sh

# Configure vSRX (see vsrx/README.md for details)
# 1. SSH to vSRX and download IDP signatures (~15-20 min)
# 2. Paste vsrx/baseline.conf into vSRX CLI

# Run demo scenarios (from Kali)
chmod +x demo/*.sh
# Copy scripts to Kali or run attacks manually

# Tear down when done
./scripts/down.sh
```

---

## Demo Scenarios

Run from Kali Linux (`ssh -i ~/.ssh/awsdemo.pem kali@<kali-eip>`):

| Script | Scenario | SRX Defense |
|---|---|---|
| `demo/01-port-scan.sh` | Port scan (nmap) | Screen: tcp/udp port-scan |
| `demo/02-syn-flood.sh` | SYN flood (hping3) | Screen: syn-flood SYN proxy |
| `demo/03-icmp-flood.sh` | ICMP flood + ping-of-death | Screen: icmp flood + large + ping-death |
| `demo/04-ssh-brute.sh` | SSH brute force (hydra) | IDP: SSH - Critical |
| `demo/05-web-attack.sh` | Web app attacks (nikto, sqlmap) | IDP: HTTP - Critical + SQL - Critical |
| `demo/06-ip-spoof.sh` | IP spoofing + malformed TCP | Screen: ip spoofing + land + syn-fin |

Each scenario follows the same flow:
1. Run attack → observe it **succeeding** (baseline state)
2. Point to the relevant vSRX defense already configured in `vsrx/baseline.conf`
3. Run `demo/verify.sh` on the vSRX → show counters incrementing / attack blocked

---

## File Structure

```
├── terraform/              # AWS infrastructure (Terraform)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc.tf              # VPC, subnets, IGW, route tables
│   ├── security_groups.tf  # 5 security groups
│   ├── instances.tf        # 3 VMs + ENIs + EIPs + ENI-dependent routes
│   ├── terraform.tfvars.example
│   └── user_data/
│       ├── kali.sh         # Install nmap, hping3, hydra, nikto, sqlmap
│       └── webserver.sh    # Apache + DVWA setup
│
├── vsrx/
│   ├── baseline.conf       # Complete Junos set-format config (paste after boot)
│   └── README.md           # Step-by-step vSRX setup guide
│
├── demo/
│   ├── 01-port-scan.sh
│   ├── 02-syn-flood.sh
│   ├── 03-icmp-flood.sh
│   ├── 04-ssh-brute.sh
│   ├── 05-web-attack.sh
│   ├── 06-ip-spoof.sh
│   └── verify.sh           # vSRX show commands (paste into vSRX CLI)
│
└── scripts/
    ├── up.sh               # terraform init + plan + apply
    └── down.sh             # confirm + terraform destroy
```
