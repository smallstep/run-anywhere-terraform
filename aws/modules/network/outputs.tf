output "vpc_id" {
  value = local.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs — internet-facing load balancers and the NAT gateway only."
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes, RDS, and ElastiCache all live here."
  value       = local.private_subnet_ids
}

output "lobby_eip_allocation_ids" {
  description = "Ordered, one per public subnet. Joined into the KOTS aws_nlb_ip config, which becomes the lobby Service's aws-load-balancer-eip-allocations annotation."
  value       = aws_eip.lobby[*].allocation_id
}

output "lobby_eip_public_ips" {
  description = "The addresses behind every lobby A record modules/dns creates."
  value       = aws_eip.lobby[*].public_ip
}
