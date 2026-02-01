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

resource "aws_organizations_organizational_unit" "base" {
  name      = "Base"
  parent_id = aws_organizations_organization.noise2signal_llc.roots[0].id

  tags = {
    Purpose = "ShoreEstablishment"
  }
}

resource "aws_organizations_organizational_unit" "domestic_fleet" {
  name      = "Domestic Fleet"
  parent_id = aws_organizations_organization.noise2signal_llc.roots[0].id

  tags = {
    Purpose = "OperatingForces"
  }
}

module "base" {
  source     = "./base"
  base_email = var.base_email
  base_ou_id = aws_organizations_organizational_unit.base.id
}

module "fleets" {
  source                      = "./fleets"
  domestic_signal_fleet_email = var.domestic_signal_fleet_email
  domestic_noise_fleet_email  = var.domestic_noise_fleet_email
  domestic_fleet_ou_id        = aws_organizations_organizational_unit.domestic_fleet.id
}

module "vice_admiral" {
  source = "./vice-admiral"
}

module "rear_admiral" {
  source            = "./rear-admiral"
  sso_admiral_email = var.sso_admiral_email
  rear_admiral_email = var.rear_admiral_email
}

module "pennants" {
  source = "./pennants"
}
