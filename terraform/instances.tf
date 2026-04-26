# ── vSRX ENIs ────────────────────────────────────────────────────────────────
# IMPORTANT: All three ENIs must be pre-created and attached at first boot via
# device_index blocks. Using aws_network_interface_attachment after launch does
# NOT guarantee Junos interface order (fxp0 / ge-0/0/0 / ge-0/0/1).
# source_dest_check MUST be false on eth1 and eth2 (revenue interfaces).

resource "aws_network_interface" "srx_mgmt" {
  subnet_id         = aws_subnet.mgmt.id
  private_ips       = ["10.0.0.10"]
  security_groups   = [aws_security_group.srx_mgmt.id]
  source_dest_check = false
  tags              = { Name = "vsrx-demo-srx-mgmt-eni" }
}

resource "aws_network_interface" "srx_untrust" {
  subnet_id         = aws_subnet.untrust.id
  private_ips       = ["10.0.1.254"]
  security_groups   = [aws_security_group.srx_untrust.id]
  source_dest_check = false
  tags              = { Name = "vsrx-demo-srx-untrust-eni" }
}

resource "aws_network_interface" "srx_trust" {
  subnet_id         = aws_subnet.trust.id
  private_ips       = ["10.0.2.254"]
  security_groups   = [aws_security_group.srx_trust.id]
  source_dest_check = false
  tags              = { Name = "vsrx-demo-srx-trust-eni" }
}

resource "aws_eip" "srx_mgmt" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.srx_mgmt.id
  associate_with_private_ip = "10.0.0.10"
  tags                      = { Name = "vsrx-demo-srx-mgmt-eip" }
}

resource "aws_eip" "srx_untrust" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.srx_untrust.id
  associate_with_private_ip = "10.0.1.254"
  tags                      = { Name = "vsrx-demo-srx-untrust-eip" }
}

# ── vSRX Instance ─────────────────────────────────────────────────────────────
# c5.2xlarge: minimum instance type for vSRX (8 vCPU, 16 GB RAM).
# ENI device_index order maps to Junos interfaces:
#   0 = fxp0 (management, out-of-band)
#   1 = ge-0/0/0 (untrust revenue interface)
#   2 = ge-0/0/1 (trust revenue interface)

resource "aws_instance" "vsrx" {
  ami           = var.vsrx_ami
  instance_type = "c5.2xlarge"
  key_name      = var.key_pair_name

  network_interface {
    network_interface_id = aws_network_interface.srx_mgmt.id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.srx_untrust.id
    device_index         = 1
  }
  network_interface {
    network_interface_id = aws_network_interface.srx_trust.id
    device_index         = 2
  }

  tags = { Name = "demo-vsrx" }
}

# ── ENI-dependent Routes ──────────────────────────────────────────────────────
# These must be created after the vSRX instance so AWS accepts the ENI as a
# valid route target (the instance must be in running/stopped state).

resource "aws_route" "untrust_to_trust" {
  route_table_id         = aws_route_table.untrust.id
  destination_cidr_block = "10.0.2.0/24"
  network_interface_id   = aws_network_interface.srx_untrust.id
  depends_on             = [aws_instance.vsrx]
}

resource "aws_route" "trust_rfc1918" {
  route_table_id         = aws_route_table.trust.id
  destination_cidr_block = "10.0.0.0/8"
  network_interface_id   = aws_network_interface.srx_trust.id
  depends_on             = [aws_instance.vsrx]
}

# ── Kali Linux Instance ───────────────────────────────────────────────────────

resource "aws_instance" "kali" {
  # Uses Ubuntu 22.04 — same as the web server. All attack tools (nmap, hping3,
  # hydra, nikto, sqlmap) are installed via user_data/kali.sh on first boot.
  # Set kali_ami in terraform.tfvars to override with an official Kali AMI.
  ami                    = var.kali_ami != "" ? var.kali_ami : data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.untrust.id
  private_ip             = "10.0.1.20"
  vpc_security_group_ids = [aws_security_group.kali.id]
  user_data              = file("${path.module}/user_data/kali.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "demo-kali" }
}

resource "aws_eip" "kali" {
  domain   = "vpc"
  instance = aws_instance.kali.id
  tags     = { Name = "vsrx-demo-kali-eip" }
}

# ── Web Server Instance ───────────────────────────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "webserver" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.trust.id
  private_ip             = "10.0.2.100"
  vpc_security_group_ids = [aws_security_group.webserver.id]
  user_data              = file("${path.module}/user_data/webserver.sh")

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "demo-webserver" }
}
