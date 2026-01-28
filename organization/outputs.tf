output "organization_id" {
  value       = aws_organizations_organization.main.id
  description = "AWS Organization ID (o-xxxxxxxxxx)"
}

output "organization_arn" {
  value       = aws_organizations_organization.main.arn
  description = "AWS Organization ARN"
}

output "organization_root_id" {
  value       = aws_organizations_organization.main.roots[0].id
  description = "Organization root ID (r-xxxx)"
}

output "management_ou_id" {
  value       = aws_organizations_organizational_unit.management.id
  description = "Management OU ID"
}

output "proprietary_workloads_ou_id" {
  value       = aws_organizations_organizational_unit.proprietary_workloads.id
  description = "Proprietary Workloads OU ID"
}

output "proprietary_signals_account_id" {
  value       = aws_organizations_account.proprietary_signals.id
  description = "Proprietary Signals account ID"
}

output "proprietary_signals_account_arn" {
  value       = aws_organizations_account.proprietary_signals.arn
  description = "Proprietary Signals account ARN"
}
