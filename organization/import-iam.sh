#!/bin/bash
set -e

echo "============================================"
echo "Importing IAM Resources"
echo "============================================"
echo ""

# Import IAM group
echo "Importing IAM Group: Noise2Signal-LLC-Admirals..."
terraform import aws_iam_group.admirals Noise2Signal-LLC-Admirals

echo ""
echo "Importing IAM Group Policy Attachment..."
terraform import aws_iam_group_policy_attachment.admirals_admin Noise2Signal-LLC-Admirals/arn:aws:iam::aws:policy/AdministratorAccess

echo ""
echo "Importing IAM User: admiral-noise2signal-llc..."
terraform import aws_iam_user.admiral admiral-noise2signal-llc

echo ""
echo "Importing IAM User Group Membership..."
terraform import aws_iam_user_group_membership.admiral_membership admiral-noise2signal-llc/Noise2Signal-LLC-Admirals

echo ""
echo "============================================"
echo "IAM import complete!"
echo "============================================"
echo ""
echo "Next: Run 'terraform plan' to verify imports"
