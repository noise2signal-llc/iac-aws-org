data "aws_ssoadmin_instances" "noise2signal_llc" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.noise2signal_llc.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.noise2signal_llc.identity_store_ids)[0]
}

resource "aws_identitystore_user" "admiral" {

  identity_store_id = local.identity_store_id

  display_name = "Admr Camden Lindahl"
  user_name = "Admiral-SSO-Noise2Signal-LLC"

  name {
    family_name = "Lindahl"
    given_name = "Admr Camden"
  }

  emails {
    primary = true
    type = "work"
    value = var.sso_admiral_email
  }
}

resource "aws_identitystore_group" "rearadmiral" {
  identity_store_id = local.identity_store_id
  display_name = "RearAdmiral"
}

resource "aws_identitystore_group_membership" "rearadmiral_orig" {
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.rearadmiral.group_id
  member_id         = aws_identitystore_user.admiral.user_id
}

resource "aws_ssoadmin_permission_set" "rearadmiral_access" {
  name             = "AdmiralAccess"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "rearadmiral_attached_policy" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.rearadmiral_access.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Reference organization to get management account ID
data "aws_organizations_organization" "noise2signal_llc" {}

resource "aws_ssoadmin_account_assignment" "management_rearadmiral" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.rearadmiral_access.arn

  principal_id   = aws_identitystore_group.rearadmiral.group_id
  principal_type = "GROUP"

  target_id   = data.aws_organizations_organization.noise2signal_llc.master_account_id
  target_type = "AWS_ACCOUNT"
}
