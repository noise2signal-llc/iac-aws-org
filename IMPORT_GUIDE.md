# Import Guide - Bringing Existing AWS Resources into Terraform

This guide walks you through importing all manually created AWS resources into Terraform state.

## Overview

You have manually created the following resources in AWS:

### AWS Organizations
- Organization: `o-9q72g05zlb`
- Management OU: `ou-zrqm-46zr6la9`
- Proprietary Workloads OU: `ou-zrqm-c2sh89s0`

### IAM Resources (Management Account)
- IAM Group: `Noise2Signal-LLC-Admirals`
- IAM User: `admiral-noise2signal-llc`
- User is member of group
- Group has AdministratorAccess policy attached

### IAM Identity Center (SSO)
- SSO User: `Admiral-SSO-Noise2Signal-LLC`
- SSO Group: `AdmiralsSSO`
- User is member of group
- Permission Set: `AdmiralAccess` (4 hour session, AdministratorAccess policy)
- Assignment: Group assigned to management account

## Import Process

### Phase 1: Organization Layer

Import AWS Organizations and IAM resources into the `organization/` layer.

```bash
cd organization/

# 1. Initialize Terraform (if not already done)
terraform init

# 2. Import Organizations resources
chmod +x import-organizations.sh
./import-organizations.sh

# 3. Import IAM resources
chmod +x import-iam.sh
./import-iam.sh

# 4. Verify all imports
terraform plan
```

**Expected Result:** `terraform plan` should show:
- 0 to add (all existing resources imported)
- 0 to change (Terraform state matches AWS)
- 1 to add (Proprietary Signals account not yet created)
- 0 to destroy

If there are differences, review the Terraform configuration to ensure it matches your AWS resources exactly.

### Phase 2: SSO Layer

Import IAM Identity Center resources into the `sso/` layer.

```bash
cd ../sso/

# 1. Initialize Terraform
terraform init

# 2. Import SSO resources
chmod +x import-sso.sh
./import-sso.sh

# 3. Verify all imports
terraform plan
```

**Expected Result:** `terraform plan` should show:
- 0 to add
- 0 to change
- 0 to destroy

### Phase 3: Verify and Commit

After all imports are successful:

```bash
# 1. Verify state files exist
ls -l organization/terraform.tfstate
ls -l sso/terraform.tfstate

# 2. Backup state files (IMPORTANT!)
cd organization/
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

cd ../sso/
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# 3. Commit Terraform code (NOT state files!)
cd ..
git add organization/*.tf organization/*.sh
git add sso/*.tf sso/*.sh
git add IMPORT_GUIDE.md
git commit -m "Add Terraform configs for existing AWS resources"

# 4. Verify .gitignore protects state files
git status
# Should NOT show any .tfstate files
```

## Troubleshooting

### Import Fails with "Resource Already Exists"

If an import fails because the resource is already in state:

```bash
# List resources in state
terraform state list

# Remove the problematic resource
terraform state rm <resource_address>

# Re-run the import
terraform import <resource_address> <resource_id>
```

### Terraform Plan Shows Unexpected Changes

After import, if `terraform plan` shows changes you don't expect:

1. **Check resource attributes:** The Terraform config might not match AWS exactly
2. **Common issues:**
   - Tags: AWS may have added tags you didn't specify
   - Default values: AWS applies defaults that need to be explicit in Terraform
   - Computed attributes: Some attributes can't be set in Terraform

**Fix:** Update the Terraform configuration to match AWS, then run `terraform plan` again.

### Import Command Syntax Errors

Each resource type has a specific import format. Refer to:
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Look for the "Import" section on each resource page

## Next Steps

After successful imports:

### Option 1: Create Proprietary Signals Account

Now that existing resources are managed by Terraform, you can create new resources:

```bash
cd organization/

# Review the plan
terraform plan

# Should show: 1 to add (aws_organizations_account.proprietary_signals)

# Create the account
terraform apply
```

### Option 2: Continue Building Infrastructure

With the foundation in place, you can:
1. Add more SSO users/groups
2. Create additional permission sets
3. Deploy the SCP layer (Service Control Policies)
4. Set up workload infrastructure in the Proprietary Signals account

## Important Reminders

### State File Security

- ✅ State files are in `.gitignore`
- ✅ Never commit state files to Git
- ✅ Backup state files before every `terraform apply`
- ✅ Store state file backups securely (encrypted USB, password manager)

### Future: Remote State Backend

Consider migrating to S3 remote state backend (see FUTURE_CONCERNS.md):
- State locking with DynamoDB
- State encryption at rest
- State versioning and history
- Team collaboration support

### Working with Terraform

**Before every `terraform apply`:**
1. Run `terraform plan` and review changes carefully
2. Backup state file: `cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)`
3. Understand what will be added/changed/destroyed
4. Apply changes: `terraform apply`

**After every `terraform apply`:**
1. Verify in AWS Console that changes are correct
2. Commit Terraform code changes to Git (not state files)
3. Document any manual steps taken

## Resources

- [Terraform Import Documentation](https://www.terraform.io/docs/cli/import/index.html)
- [AWS Organizations Terraform Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization)
- [IAM Terraform Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user)
- [SSO Admin Terraform Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set)

---

**Last Updated:** 2026-01-28
**Status:** Ready for import
