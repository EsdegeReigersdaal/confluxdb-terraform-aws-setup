output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The primary CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  description = "List of IDs of public subnets."
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets."
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "List of IDs of database subnets."
  value       = module.vpc.database_subnets
}

output "nat_public_ips" {
  description = "List of public Elastic IP addresses assigned to the NAT Gateways."
  value       = module.vpc.nat_public_ips
}

output "default_security_group_id" {
  description = "The ID of the default security group for the VPC."
  value       = module.vpc.default_security_group_id
}
