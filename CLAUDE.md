# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A self-contained AWS lab for demonstrating Juniper vSRX NGFW capabilities against live attacks. Three VMs: Kali Linux (attacker), vSRX firewall, Ubuntu web server (DVWA). All Kali→web traffic is forced through the vSRX via AWS route tables — the vSRX does pure routing (no NAT).

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
```

## Critical architecture constraints

**vSRX ENI ordering** (`terraform/instances.tf`): All three ENIs must be pre-created as `aws_network_interface` resources and attached via `network_interface { device_index = N }` blocks inside `aws_instance` — never via `aws_network_interface_attachment` after launch. The order is fixed: `device_index=0` → `fxp0` (mgmt), `device_index=1` → `ge-0/0/0` (untrust), `device_index=2` → `ge-0/0/1` (trust). Getting this wrong means the Junos interface names won't match the config.

**source_dest_check**: Must be `false` on all three vSRX `aws_network_interface` resources. Setting it on the `aws_instance` resource instead does not work when `network_interface` blocks are used.

**ENI-dependent routes**: The two routes that point to vSRX ENIs (`aws_route.untrust_to_trust` and `aws_route.trust_default`) have `depends_on = [aws_instance.vsrx]` because AWS requires the ENI to be attached to a running instance before accepting it as a route target. These are in `instances.tf`, not `vpc.tf`, to make the dependency clear.

**Route table design** (why traffic flows through the SRX):
- Untrust subnet RT: `10.0.2.0/24 → srx_untrust ENI` — forces Kali→web through SRX
- Trust subnet RT: `0.0.0.0/0 → srx_trust ENI` — web server's default gateway is the SRX
- AWS SGs allow traffic from the full VPC CIDR (10.0.0.0/16) on the web server because Kali's source IP is not NATted — it arrives at the web server as 10.0.1.x. The vSRX is the enforcement point, not the SG.

**vSRX bootstrap is manual**: There is no Terraform provisioner for vSRX config. After `terraform apply`, follow `vsrx/README.md`: SSH in, download IDP signatures (~15–20 min), then paste `vsrx/baseline.conf` into the CLI. The IDP policy in `baseline.conf` won't activate until signatures are installed — do the download first.

## IP address map

| Host | Interface | IP |
|---|---|---|
| vSRX | fxp0 (mgmt) | 10.0.0.10 + EIP |
| vSRX | ge-0/0/0 (untrust) | 10.0.1.254 |
| vSRX | ge-0/0/1 (trust) | 10.0.2.254 |
| Kali | eth0 | 10.0.1.20 + EIP |
| Web server | eth0 | 10.0.2.100 |

AWS VPC router is always `.1` in each subnet (10.0.0.1, 10.0.1.1, 10.0.2.1).

## Junos config structure (`vsrx/baseline.conf`)

The config is all-in-one set format. Key design choices:
- The `untrust-screen` has **all** screen protections defined at baseline. During a live demo, show the attack succeeding first (the screen counters prove the attack hit), then explain the config is protecting it.
- The IDP policy `demo-idp` covers three rule groups: `SSH - Critical`, `HTTP - Critical`, `SQL - Critical`. It's attached to the security policy via `application-services idp-policy demo-idp`.
- fxp0 gets its IP from DHCP (AWS assigns it) — do not add a static `fxp0` address to the config or it will conflict.

## Demo flow

Each of the 6 `demo/` scripts runs from Kali. The expected flow per scenario:
1. Run attack → observe it reaching/affecting the web server (baseline permits it, screen counters show hits)
2. Reference the relevant lines in `vsrx/baseline.conf` explaining what blocks it
3. Run `demo/verify.sh` commands on vSRX to show counters/IDP table

Scenarios 4 (SSH brute) and 5 (web attacks) require IDP signatures — must be downloaded before demo day.

## Variables required in `terraform/terraform.tfvars`

- `admin_cidr` — your public IP as `/32` (find with `curl ifconfig.me`)
- `key_pair_name` — name of an existing AWS key pair
- `vsrx_ami` — region-specific AMI ID, found after subscribing to vSRX NGFW PAYG on AWS Marketplace
- `aws_region` — defaults to `ap-southeast-1`; vSRX PAYG AMI is available there

The Kali AMI auto-discovers via `data "aws_ami"` (requires Marketplace subscription). Provide `kali_ami` explicitly if the lookup fails.
