resource "aws_organizations_account" "management" {
  name              = "Noise2Signal LLC"
  email             = var.management_account_email
  parent_id         = aws_organizations_organizational_unit.management.id
  close_on_deletion = true
 
  tags = {
    Purpose = "FleetOperations"
  }
}

resource "aws_organizations_account" "proprietary_signals" {
  name              = "Proprietary Signals"
  email             = var.proprietary_signals_account_email
  parent_id         = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = true

  tags = {
    Purpose = "Deployments"
  }
}

resource "aws_organizations_account" "proprietary_noise" {
  name = "Propreitary Noise"
  email = var.proprietary_noise_account_email
  parent_id = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = true

  tags = {
    Purpose = "Readiness"
  }
}
