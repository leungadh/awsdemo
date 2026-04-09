variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32) — used for SSH access to vSRX mgmt and Kali"
  type        = string
}

variable "key_pair_name" {
  description = "Name of an existing AWS key pair for SSH access to all instances"
  type        = string
}

variable "vsrx_ami" {
  description = <<-EOT
    vSRX PAYG NGFW AMI ID (region-specific).
    You MUST subscribe to the Juniper vSRX NGFW PAYG product on AWS Marketplace first.
    After subscribing, find the AMI ID under: Marketplace > Manage subscriptions >
    vSRX > Continue to Configuration > select your region.
  EOT
  type        = string
}

variable "kali_ami" {
  description = <<-EOT
    Kali Linux AMI ID (optional).
    Leave empty to auto-discover via data source (requires Marketplace subscription).
    Provide explicitly if the data source lookup fails.
  EOT
  type        = string
  default     = ""
}
