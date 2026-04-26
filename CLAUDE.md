# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A self-contained AWS lab for demonstrating Juniper vSRX NGFW capabilities against live attacks. Three VMs: Kali Linux (attacker), vSRX firewall, Ubuntu web server (DVWA). All Kali→web traffic is forced through the vSRX via AWS route tables — the vSRX does pure routing (no NAT for demo traffic).

## Commands

```bash
# Bring up the environment (~5 min)
./scripts/up.sh

# Tear down everything
./scripts/down.sh

# Validate Terraform without applying
cd terraform && terraform validate
cd terraform && terraform plan

# Check what outputs (IPs) Terraform knows about
cd terraform && terraform output

# Start the live dashboard (auto-opens http://localhost:8080)
cd dashboard && uv run dashboard.py
```

## Critical architecture constraints

**vSRX ENI ordering** (`terraform/instances.tf`): All three ENIs must be pre-created as `aws_network_interface` resources and attached via `network_interface { device_index = N }` blocks inside `aws_instance` — never via `aws_network_interface_attachment` after launch. The order is fixed: `device_index=0` → `fxp0` (mgmt), `device_index=1` → `ge-0/0/0` (untrust), `device_index=2` → `ge-0/0/1` (trust). Getting this wrong means the Junos interface names won't match the config.

**source_dest_check**: Must be `false` on all three vSRX `aws_network_interface` resources. Setting it on the `aws_instance` resource instead does not work when `network_interface` blocks are used.

**ENI-dependent routes**: The routes that point to vSRX ENIs (`aws_route.untrust_to_trust` and `aws_route.trust_rfc1918`) have `depends_on = [aws_instance.vsrx]` because AWS requires the ENI to be attached to a running instance before accepting it as a route target. These are in `instances.tf`, not `vpc.tf`, to make the dependency clear.

**Route table design** (why traffic flows through the SRX):
- Untrust subnet RT: `10.0.2.0/24 → srx_untrust ENI` — forces Kali→web through SRX
- Trust subnet RT: `10.0.0.0/8 → srx_trust ENI` — return traffic to any RFC1918 address goes through SRX; `0.0.0.0/0 → NAT GW` — internet-bound traffic (apt-get, DVWA setup) exits via NAT GW in the mgmt subnet
- The `10.0.0.0/16 local` route in the trust RT takes precedence over `10.0.0.0/8` for intra-VPC traffic, so return traffic from the web server to Kali actually routes directly (via local). The SRX enforcement is on the **forward path** (Kali→web), which is what the demo shows.
- AWS SGs allow traffic from the full VPC CIDR (10.0.0.0/16) on the web server because Kali's source IP is not NATted — it arrives at the web server as 10.0.1.x. The vSRX is the primary enforcement point, not the SG.

**NAT gateway** is placed in the **mgmt subnet** (not untrust). If placed in the untrust subnet, return packets from the NAT GW to the trust subnet would be routed via the vSRX untrust ENI (per the `10.0.2.0/24 → srx_untrust ENI` route), causing asymmetric routing and dropped sessions. In the mgmt subnet, return packets use the local route directly.

**vSRX EIPs**: Both fxp0 (mgmt) and ge-0/0/0 (untrust) have EIPs. The untrust EIP is required for the vSRX data-plane routing instance to reach the internet (for IDP signature downloads and license updates). Without it, `request security idp security-package download` fails with "Server not reachable".

**set system management-instance**: Must be in the vSRX config before `set routing-options static route 0.0.0.0/0`. This isolates fxp0 into a separate routing instance (`mgmt_junos`), preventing the data-plane default route from routing SSH return traffic out the wrong interface and breaking management access. Without it, committing the config causes SSH timeout.

**vSRX bootstrap is manual, split into two phases**:
- `vsrx/baseline-phase1.conf` — interfaces, zones, screens, security policy (no IDP). Apply first, verify SSH + traffic flow work.
- `vsrx/baseline-phase2.conf` — IDP policy only. Apply after phase 1 is verified AND IDP signatures are installed.
- IDP signatures must be downloaded/installed before applying phase 2: `request security idp security-package download full-update` then `request security idp security-package install`.
- **IDP-SIG license**: The PAYG NGFW AMI bundles a `JuniperEval` trial license that does NOT include IDP-SIG. `request security idp security-package install` will fail with "invalid license" until an IDP-SIG license is added. Obtain a free 60-day eval from Juniper's portal and add via `request system license add terminal`.

**Junos version-specific quirks** (Junos 24.4R2-S3.5 on this AMI):
- `set security screen ids-option untrust-screen icmp address-sweep threshold N` — syntax error, not supported. Removed from baseline config.
- `set security screen ids-option untrust-screen tcp no-flag` — syntax error, not supported. Removed from baseline config.
- `clear security screen statistics` — requires `interface ge-0/0/0` argument; bare command fails with "missing argument".

## IP address map

| Host | Interface | IP | Public IP |
|---|---|---|---|
| vSRX | fxp0 (mgmt) | 10.0.0.10 | EIP (dynamic) |
| vSRX | ge-0/0/0 (untrust) | 10.0.1.254 | EIP (dynamic) |
| vSRX | ge-0/0/1 (trust) | 10.0.2.254 | — |
| Kali | eth0 | 10.0.1.20 | EIP (dynamic) |
| Web server | eth0 | 10.0.2.100 | — |

AWS VPC router is always `.1` in each subnet (10.0.0.1, 10.0.1.1, 10.0.2.1).
SSH user for Kali is `ubuntu` (not `kali`). SSH user for vSRX is `ec2-user`.

## Junos config structure

The config is split-format. Key design choices:
- `set system management-instance` isolates fxp0 — must come before the default route.
- The `untrust-screen` has all supported screen protections. Screen counters prove attacks hit the firewall during the demo.
- The IDP policy `demo-idp` covers three rule groups: `SSH - Critical`, `HTTP - Critical`, `SQL - Critical`. It's attached to the security policy via `application-services idp-policy demo-idp`.
- fxp0 gets its IP from DHCP (AWS assigns it) — do not add a static `fxp0` address to the config.

## Demo flow

Each of the 6 `demo/` scripts runs from Kali (`ssh -i ~/.ssh/awsdemo.pem ubuntu@<kali-eip>`). Scripts are pre-copied to `~/demo/` on the Kali VM.

1. Run attack → observe it reaching/affecting the web server (screen counters show hits)
2. Reference the relevant lines in `vsrx/baseline-phase1.conf` explaining what blocks it
3. Run `demo/verify.sh` commands on vSRX to show counters

Scenarios 4 (SSH brute) and 5 (web attacks) print a clear "IDP-SIG license required" message and exit without running. All other scenarios work without IDP.

## Dashboard

`dashboard/dashboard.py` — live browser dashboard at http://localhost:8080. Polls the vSRX via SSH (asyncssh) and AWS EC2 API (boto3) every 15 seconds. Shows topology, node health, screen counters, and security log.

Run with: `cd dashboard && uv run dashboard.py` (uv manages deps automatically via PEP 723 inline metadata).

Config is read from `dashboard/config.yaml` (copy from `config.yaml.example`). `vsrx_public_ip` is auto-detected from `terraform output` if left blank.

## Variables required in `terraform/terraform.tfvars`

- `admin_cidr` — your public IP as `/32` (find with `curl ifconfig.me`)
- `key_pair_name` — name of an existing AWS key pair
- `vsrx_ami` — region-specific AMI ID, found after subscribing to vSRX NGFW PAYG on AWS Marketplace
- `aws_region` — defaults to `ap-southeast-1`; vSRX PAYG AMI is available there

The Kali AMI auto-discovers via `data "aws_ami"` (requires Marketplace subscription). Provide `kali_ami` explicitly if the lookup fails.
