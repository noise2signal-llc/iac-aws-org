resource "aws_organizations_organization" "noise2signal_llc" {
  aws_service_access_principals = [
    "sso.amazonaws.com",
    "iam.amazonaws.com",
  ]

  enabled_policy_types = [
    # "SERVICE_CONTROL_POLICY", # For future SCP implementation
  ]

  feature_set = "ALL"
}

resource "aws_organizations_organizational_unit" "management" {
  name      = "Noise2Signal LLC Management"
  parent_id = aws_organizations_organization.noise2signal_llc.roots[0].id
}

resource "aws_organizations_organizational_unit" "proprietary_workloads" {
  name      = "Proprietary Workloads"
  parent_id = aws_organizations_organization.noise2signal_llc.roots[0].id
}

