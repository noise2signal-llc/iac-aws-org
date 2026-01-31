resource "aws_organizations_account" "management" {
  name              = "Noise2Signal LLC"
  email             = var.base_email
  parent_id         = var.base_ou_id
  close_on_deletion = true

  tags = {
    Purpose = "FleetOperations"
  }
}

