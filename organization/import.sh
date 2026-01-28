#!/bin/bash
set -e

echo "============================================"
echo "AWS Organizations Terraform Import Script"
echo "============================================"
echo ""
echo "This script will help you import existing AWS"
echo "Organizations resources into Terraform state."
echo ""

# Get Organization ID
echo "Step 1: Getting Organization ID..."
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)
echo "Organization ID: $ORG_ID"
echo ""

# Get Root ID
echo "Step 2: Getting Root ID..."
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root ID: $ROOT_ID"
echo ""

# List OUs
echo "Step 3: Listing Organizational Units..."
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID
echo ""

# Get OU IDs (user will need to input these)
echo "Step 4: Enter OU IDs from the output above"
read -p "Enter Management OU ID (ou-xxxx-xxxxxxxx): " MGMT_OU_ID
read -p "Enter Proprietary Workloads OU ID (ou-xxxx-xxxxxxxx): " PROP_OU_ID
echo ""

# Confirm before importing
echo "============================================"
echo "Ready to import the following resources:"
echo "  - Organization: $ORG_ID"
echo "  - Root: $ROOT_ID"
echo "  - Management OU: $MGMT_OU_ID"
echo "  - Proprietary Workloads OU: $PROP_OU_ID"
echo "============================================"
read -p "Proceed with import? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Import cancelled."
    exit 0
fi

# Import resources
echo ""
echo "Importing AWS Organization..."
terraform import aws_organizations_organization.main $ORG_ID

echo ""
echo "Importing Management OU..."
terraform import aws_organizations_organizational_unit.management $MGMT_OU_ID

echo ""
echo "Importing Proprietary Workloads OU..."
terraform import aws_organizations_organizational_unit.proprietary_workloads $PROP_OU_ID

echo ""
echo "============================================"
echo "Import complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to verify imports"
echo "2. If there are differences, update Terraform code to match AWS"
echo "3. Create terraform.tfvars with Proprietary Signals email"
echo "4. Run 'terraform apply' to create the Proprietary Signals account"
