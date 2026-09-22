output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Delegate these in the parent zone. Nothing in this zone resolves until that happens."
  value       = aws_route53_zone.this.name_servers
}
