#!/bin/bash
set -e

echo "============================================"
echo "Importing IAM Identity Center Resources"
echo "============================================"
echo ""

# Set variables
IDENTITY_STORE_ID="d-90661c3f26"
INSTANCE_ARN="arn:aws:sso:::instance/ssoins-7223eb760e17d340"
PERMISSION_SET_ARN="arn:aws:sso:::permissionSet/ssoins-7223eb760e17d340/ps-b8d9149a94761980"
GROUP_ID="d42854b8-90b1-707f-0963-d6ba952ddc73"
USER_ID="64980458-9001-700f-f430-6ea09c1a8666"
MEMBERSHIP_ID="b4a87408-5031-7085-4668-53e460dc1032"
ACCOUNT_ID="922544547398"

# Import group membership
echo "Importing Identity Store Group Membership..."
terraform import aws_identitystore_group_membership.admiral_to_admirals \
  "${IDENTITY_STORE_ID}/${MEMBERSHIP_ID}"

echo ""
echo "Importing Permission Set: AdmiralAccess..."
terraform import aws_ssoadmin_permission_set.admiral_access \
  "${PERMISSION_SET_ARN},${INSTANCE_ARN}"

echo ""
echo "Importing Managed Policy Attachment..."
terraform import aws_ssoadmin_managed_policy_attachment.admiral_access_admin_policy \
  "arn:aws:iam::aws:policy/AdministratorAccess,${PERMISSION_SET_ARN},${INSTANCE_ARN}"

echo ""
echo "Importing Account Assignment (Group to Management Account)..."
terraform import aws_ssoadmin_account_assignment.admirals_to_management \
  "${GROUP_ID},GROUP,${ACCOUNT_ID},AWS_ACCOUNT,${PERMISSION_SET_ARN},${INSTANCE_ARN}"

echo ""
echo "============================================"
echo "SSO import complete!"
echo "============================================"
echo ""
echo "Next: Run 'terraform plan' to verify imports"
