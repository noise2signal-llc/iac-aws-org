# AWS Organization
# Status: Exists in AWS, needs import
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = var.aws_service_access_principals

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",  # For future SCP implementation
  ]

  feature_set = "ALL"
}

# Management OU
# Status: Exists in AWS, needs import
resource "aws_organizations_organizational_unit" "management" {
  name      = "Noise2Signal LLC Management"
  parent_id = aws_organizations_organization.main.roots[0].id
}

# Proprietary Workloads OU
# Status: Exists in AWS, needs import
resource "aws_organizations_organizational_unit" "proprietary_workloads" {
  name      = "Proprietary Workloads"
  parent_id = aws_organizations_organization.main.roots[0].id
}

# Proprietary Signals Account
# Status: To be created via Terraform (Phase 2)
resource "aws_organizations_account" "proprietary_signals" {
  name              = "Proprietary Signals"
  email             = var.proprietary_signals_email
  parent_id         = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = false

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "proprietary-signals"
    CostCenter   = "proprietary"
    Environment  = "production"
    ManagedBy    = "terraform"
    Purpose      = "workload-production"
  }
}
