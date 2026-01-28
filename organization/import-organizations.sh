#!/bin/bash
set -e

echo "============================================"
echo "Importing AWS Organizations Resources"
echo "============================================"
echo ""

# Import organization
echo "Importing AWS Organization..."
terraform import aws_organizations_organization.noise2signal_llc o-9q72g05zlb

echo ""
echo "Importing Management OU..."
terraform import aws_organizations_organizational_unit.management ou-zrqm-46zr6la9

echo ""
echo "Importing Proprietary Workloads OU..."
terraform import aws_organizations_organizational_unit.proprietary_workloads ou-zrqm-c2sh89s0

echo ""
echo "============================================"
echo "Organizations import complete!"
echo "============================================"
echo ""
echo "Next: Run 'terraform plan' to verify imports"
