resource "aws_organizations_account" "domestic_signals" {
  name              = "Domestic Signals"
  email             = var.domestic_signal_fleet_email
  parent_id         = var.domestic_fleet_ou_id # aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = true

  tags = {
    Purpose = "Deployments"
  }
}

resource "aws_organizations_account" "domestic_noise" {
  name              = "Domestic Noise"
  email             = var.domestic_noise_fleet_email
  parent_id         = var.domestic_fleet_ou_id # aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = true

  tags = {
    Purpose = "Readiness"
  }
}
