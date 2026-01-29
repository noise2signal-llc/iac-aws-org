resource "aws_organizations_account" "management" {
  name              = "Noise2Signal LLC"
  email             = var.member_email
  parent_id         = aws_organizations_organizational_unit.management.id
  close_on_deletion = true
}

resource "aws_organizations_account" "proprietary_signals" {
  name              = "Proprietary Signals"
  email             = var.proprietary_signals_email
  parent_id         = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = true
}
