resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "vsrx-demo-vpc" }
}

# ── Subnets ──────────────────────────────────────────────────────────────────

resource "aws_subnet" "mgmt" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "vsrx-demo-mgmt" }
}

resource "aws_subnet" "untrust" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "vsrx-demo-untrust" }
}

resource "aws_subnet" "trust" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "vsrx-demo-trust" }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "vsrx-demo-igw" }
}

# ── Route Tables ──────────────────────────────────────────────────────────────

# Mgmt: default route to internet (for SSH + vSRX IDP signature download)
resource "aws_route_table" "mgmt" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "vsrx-demo-mgmt-rt" }
}

resource "aws_route" "mgmt_default" {
  route_table_id         = aws_route_table.mgmt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Untrust: default to internet (Kali needs internet for tool updates + package installs)
#          plus 10.0.2.0/24 → vSRX untrust ENI (forces Kali→web traffic through SRX)
#          The 10.0.2.0/24 route is added in instances.tf after the ENI is created.
resource "aws_route_table" "untrust" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "vsrx-demo-untrust-rt" }
}

resource "aws_route" "untrust_default" {
  route_table_id         = aws_route_table.untrust.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Trust: internet via NAT GW (web server package installs),
#        RFC1918 via vSRX trust ENI (attack return traffic stays inspected).
#        The 10.0.0.0/8 route is added in instances.tf after the ENI is created.
resource "aws_route_table" "trust" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "vsrx-demo-trust-rt" }
}

# NAT Gateway for web server outbound internet (apt-get, DVWA installs)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "vsrx-demo-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.mgmt.id
  tags          = { Name = "vsrx-demo-nat-gw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route" "trust_internet" {
  route_table_id         = aws_route_table.trust.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# ── Route Table Associations ──────────────────────────────────────────────────

resource "aws_route_table_association" "mgmt" {
  subnet_id      = aws_subnet.mgmt.id
  route_table_id = aws_route_table.mgmt.id
}

resource "aws_route_table_association" "untrust" {
  subnet_id      = aws_subnet.untrust.id
  route_table_id = aws_route_table.untrust.id
}

resource "aws_route_table_association" "trust" {
  subnet_id      = aws_subnet.trust.id
  route_table_id = aws_route_table.trust.id
}
