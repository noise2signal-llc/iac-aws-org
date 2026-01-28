resource "aws_organizations_organization" "noise2signal_llc" {
  aws_service_access_principals = var.aws_service_access_principals

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",  # For future SCP implementation
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

resource "aws_iam_group" "admirals" {
  name = "Noise2Signal-LLC-Admirals"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "admirals_admin" {
  group      = aws_iam_group.admirals.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user" "admiral" {
  name = "admiral-noise2signal-llc"
  path = "/"

  tags = {
    Role         = "admiral"
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
  }
}

# Add Admiral user to Admirals group
# Status: Exists in AWS, needs import
resource "aws_iam_user_group_membership" "admiral_membership" {
  user = aws_iam_user.admiral.name

  groups = [
    aws_iam_group.admirals.name,
  ]
}

# Proprietary Signals Account
# Status: To be created via Terraform (Phase 2)
resource "aws_organizations_account" "proprietary_signals" {
  name              = "Proprietary Signals"
  email             = var.proprietary_signals_email
  parent_id         = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = false

  tags = {
    Account      = "proprietary-signals"
    CostCenter   = "Noise2Signal LLC"
    ManagedBy    = "terraform"
    Purpose      = "live-proprietary-workloads"
  }
}
