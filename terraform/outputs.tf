output "vsrx_mgmt_public_ip" {
  description = "vSRX management EIP — use this to SSH into the firewall"
  value       = aws_eip.srx_mgmt.public_ip
}

output "vsrx_untrust_ip" {
  description = "vSRX ge-0/0/0 IP (untrust side)"
  value       = "10.0.1.254"
}

output "vsrx_trust_ip" {
  description = "vSRX ge-0/0/1 IP (trust side)"
  value       = "10.0.2.254"
}

output "kali_public_ip" {
  description = "Kali Linux public IP — SSH here to run attacks"
  value       = aws_eip.kali.public_ip
}

output "webserver_private_ip" {
  description = "Web server private IP (reachable only through vSRX)"
  value       = "10.0.2.100"
}

output "ssh_vsrx" {
  description = "SSH command to connect to vSRX management interface"
  value       = "ssh -i ~/.ssh/<your-key>.pem ec2-user@${aws_eip.srx_mgmt.public_ip}"
}

output "ssh_kali" {
  description = "SSH command to connect to Kali attacker VM"
  value       = "ssh -i ~/.ssh/<your-key>.pem ubuntu@${aws_eip.kali.public_ip}"
}
