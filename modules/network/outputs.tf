output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability Zones in use."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT)."
  value       = [for s in aws_subnet.public : s.id]
}

output "app_subnet_ids" {
  description = "Private app subnet IDs (ECS tasks)."
  value       = [for s in aws_subnet.app : s.id]
}

output "data_subnet_ids" {
  description = "Isolated data subnet IDs (RDS)."
  value       = [for s in aws_subnet.data : s.id]
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateway(s); all outbound app traffic appears from these."
  value       = [for e in aws_eip.nat : e.public_ip]
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
