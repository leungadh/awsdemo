# ── vSRX Management SG (applied to fxp0 / eth0) ──────────────────────────────
# Allows SSH/HTTPS from operator only. Allows all outbound for IDP signature downloads.

resource "aws_security_group" "srx_mgmt" {
  name        = "vsrx-demo-srx-mgmt"
  description = "vSRX management interface - SSH from operator only"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "HTTPS (J-Web) from operator"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound - needed for IDP signature downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vsrx-demo-srx-mgmt" }
}

# ── vSRX Untrust SG (applied to ge-0/0/0 / eth1) ────────────────────────────
# Open to all inbound — attack traffic from Kali must reach this interface.
# Security enforcement happens inside the vSRX, not at the AWS SG level.

resource "aws_security_group" "srx_untrust" {
  name        = "vsrx-demo-srx-untrust"
  description = "vSRX untrust interface - receives all attack traffic from Kali"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "All inbound (attack traffic for demo)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vsrx-demo-srx-untrust" }
}

# ── vSRX Trust SG (applied to ge-0/0/1 / eth2) ──────────────────────────────

resource "aws_security_group" "srx_trust" {
  name        = "vsrx-demo-srx-trust"
  description = "vSRX trust interface - communicates with web server subnet"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "Return traffic from trust subnet (web server responses)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vsrx-demo-srx-trust" }
}

# ── Kali SG ──────────────────────────────────────────────────────────────────

resource "aws_security_group" "kali" {
  name        = "vsrx-demo-kali"
  description = "Kali attacker VM - SSH from operator, all outbound"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vsrx-demo-kali" }
}

# ── Web Server SG ─────────────────────────────────────────────────────────────
# NOTE: AWS SGs are evaluated at the ENI level. Kali's packets arrive at the
# web server with their original source IP (10.0.1.x). The SRX does NOT NAT.
# Therefore this SG allows traffic from the full VPC CIDR. The vSRX is the
# primary enforcement point — this SG is just a backstop.

resource "aws_security_group" "webserver" {
  name        = "vsrx-demo-webserver"
  description = "Web server - traffic arrives from VPC (via vSRX routing, no NAT)"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "ICMP from VPC (ping for connectivity testing)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTP from VPC (Kali traffic passes through vSRX routing)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "SSH from operator (direct management access)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "SSH from VPC (jump via Kali for troubleshooting)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vsrx-demo-webserver" }
}
