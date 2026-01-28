data "aws_ssoadmin_instances" "noise2signal_llc" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.noise2signal_llc.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.noise2signal_llc.identity_store_ids)[0]
}

data "aws_identitystore_user" "admiral" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "Admiral-SSO-Noise2Signal-LLC"
    }
  }
}

data "aws_identitystore_group" "admirals" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "AdmiralsSSO"
    }
  }
}

resource "aws_identitystore_group_membership" "admiral_to_admirals" {
  identity_store_id = local.identity_store_id
  group_id          = data.aws_identitystore_group.admirals.group_id
  member_id         = data.aws_identitystore_user.admiral.user_id
}

# Permission Set: AdmiralAccess
# Status: Exists in AWS, needs import
resource "aws_ssoadmin_permission_set" "admiral_access" {
  name             = "AdmiralAccess"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"

  tags = merge(
    var.common_tags,
    {
      PermissionSet = "admiral-access"
    }
  )
}

# Attach AdministratorAccess policy to AdmiralAccess permission set
# Status: Exists in AWS, needs import
resource "aws_ssoadmin_managed_policy_attachment" "admiral_access_admin_policy" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admiral_access.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Reference organization to get management account ID
data "aws_organizations_organization" "noise2signal_llc" {}

# Assign AdmiralsSSO group to management account with AdmiralAccess permission set
# Status: Exists in AWS, needs import
resource "aws_ssoadmin_account_assignment" "admirals_to_management" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admiral_access.arn

  principal_id   = data.aws_identitystore_group.admirals.group_id
  principal_type = "GROUP"

  target_id   = data.aws_organizations_organization.noise2signal_llc.master_account_id
  target_type = "AWS_ACCOUNT"
}
