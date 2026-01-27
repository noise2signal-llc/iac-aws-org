# Organization Layer - AWS Organizations Structure

## Purpose

The **organization layer** manages the AWS Organization structure, organizational units (OUs), and member accounts. This is the foundation of the multi-account architecture.

**Layer 0** - Foundation layer for all other infrastructure

---

## Current State

### Resources Already Created (Need Import)

The following resources were created manually in the AWS console and need to be imported into Terraform:

**AWS Organization:**
- ✓ Organization enabled (management account: Noise2Signal LLC)
- ✓ Consolidated billing active
- ✓ Feature set: ALL

**Organizational Units:**
- ✓ Management OU: "Noise2Signal LLC Management"
- ✓ Proprietary Workloads OU

**Accounts:**
- ✓ Noise2Signal LLC (management account, automatically in org)

### Resources to Create via Terraform

**Next Step:**
- → Proprietary Signals account (production workload account under Proprietary Workloads OU)

**Future:**
- Proprietary Noise account (development workload account - deferred)
- Client OUs and accounts (see FUTURE_CONCERNS.md)

---

## Resources Managed by This Layer

### AWS Organization

```hcl
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "sso.amazonaws.com",  # IAM Identity Center
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",  # For future SCP implementation
  ]

  feature_set = "ALL"
}
```

**Status:** ✓ Exists, needs import

**To import:**
```bash
# Get organization ID
aws organizations describe-organization --query 'Organization.Id' --output text

# Import into Terraform
terraform import aws_organizations_organization.main <organization-id>
```

### Organizational Units

**Management OU:**
```hcl
resource "aws_organizations_organizational_unit" "management" {
  name      = "Noise2Signal LLC Management"
  parent_id = aws_organizations_organization.main.roots[0].id
}
```

**Status:** ✓ Exists, needs import

**Proprietary Workloads OU:**
```hcl
resource "aws_organizations_organizational_unit" "proprietary_workloads" {
  name      = "Proprietary Workloads"
  parent_id = aws_organizations_organization.main.roots[0].id
}
```

**Status:** ✓ Exists, needs import

**To import:**
```bash
# Get root ID
aws organizations list-roots --query 'Roots[0].Id' --output text

# List OUs to get IDs
aws organizations list-organizational-units-for-parent --parent-id <root-id>

# Import Management OU
terraform import aws_organizations_organizational_unit.management <management-ou-id>

# Import Proprietary Workloads OU
terraform import aws_organizations_organizational_unit.proprietary_workloads <proprietary-workloads-ou-id>
```

### Current OU Structure

```
Organization Root
├── Noise2Signal LLC Management (OU)
│   └── Noise2Signal LLC (Management Account) ✓ EXISTS
│
└── Proprietary Workloads (OU)
    ├── Proprietary Signals → TO CREATE VIA TERRAFORM
    └── Proprietary Noise → FUTURE (deferred)
```

### Member Accounts

**Management Account (automatic):**
The management account (Noise2Signal LLC) is automatically part of the organization and doesn't need to be created as a separate resource.

**Proprietary Signals Account (to create):**
```hcl
resource "aws_organizations_account" "proprietary_signals" {
  name              = "Proprietary Signals"
  email             = "aws+proprietary-signals@noise2signal.com"  # UPDATE
  parent_id         = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = false

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "proprietary-signals"
    CostCenter   = "proprietary"
    Environment  = "production"
    ManagedBy    = "terraform"
    Purpose      = "workload-production"
  }
}
```

**Status:** → To create (next step)

**Key Points:**
- Email must be unique across all AWS accounts globally
- Account creation takes 5-15 minutes
- Root user email = specified email address
- Root user password must be set via "Forgot Password" flow
- Management account can assume `OrganizationAccountAccessRole` in new account

---

## Deployment Phases

### Phase 1: Import Existing Resources

**Prerequisites:**
- AWS CLI configured with management account credentials
- Organization already enabled (✓ done)
- OUs already created (✓ done)

**Step 1: Initialize Terraform**
```bash
cd organization/
terraform init
```

**Step 2: Create Terraform Configuration**

Create `main.tf` with resources matching existing AWS state (see "Resources Managed" section above).

**Step 3: Import Organization**
```bash
# Get IDs from AWS
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)

echo "Organization ID: $ORG_ID"
echo "Root ID: $ROOT_ID"

# Import organization
terraform import aws_organizations_organization.main $ORG_ID
```

**Step 4: Import OUs**
```bash
# List OUs to get their IDs
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID

# Get OU IDs (replace with actual IDs from output)
MGMT_OU_ID="ou-xxxx-xxxxxxxx"  # Management OU ID
PROP_OU_ID="ou-xxxx-xxxxxxxx"  # Proprietary Workloads OU ID

# Import OUs
terraform import aws_organizations_organizational_unit.management $MGMT_OU_ID
terraform import aws_organizations_organizational_unit.proprietary_workloads $PROP_OU_ID
```

**Step 5: Verify Import**
```bash
terraform plan
```

**Expected output:** No changes needed (all resources imported successfully)

If there are differences, update the Terraform code to match actual AWS state, then run `terraform plan` again.

---

### Phase 2: Create Proprietary Signals Account

**Prerequisites:**
- Phase 1 completed (existing resources imported)
- Unique email address for new account
- `terraform.tfvars` configured

**Step 1: Configure Variables**

Create `terraform.tfvars`:
```hcl
proprietary_signals_email = "aws+proprietary-signals@noise2signal.com"
```

**Important:** Add `*.tfvars` to `.gitignore` (contains email addresses)

**Step 2: Plan New Account**
```bash
terraform plan
```

**Expected:** 1 resource to create (`aws_organizations_account.proprietary_signals`)

**Step 3: Create Account**
```bash
terraform apply
```

**Timeline:** 5-15 minutes for account provisioning

**Step 4: Verify Account Creation**
```bash
# Get account ID from Terraform output
terraform output proprietary_signals_account_id

# List all accounts
aws organizations list-accounts

# Verify account is in correct OU
aws organizations list-accounts-for-parent --parent-id $PROP_OU_ID
```

**Step 5: Configure Root User Access**

The new account's root user:
- Email: `aws+proprietary-signals@noise2signal.com`
- Password: Not set (use "Forgot Password" flow)
- MFA: Not enabled (should enable after password reset)

**Set root password:**
1. Go to AWS Console login page
2. Click "Forgot Password"
3. Enter account email address
4. Follow email instructions
5. Enable MFA (virtual or hardware token)

---

## Variables

### Required Variables

```hcl
variable "proprietary_signals_email" {
  type        = string
  description = "Email address for Proprietary Signals account root user (must be globally unique)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.proprietary_signals_email))
    error_message = "Must be a valid email address."
  }
}
```

### Optional Variables

```hcl
variable "aws_service_access_principals" {
  type        = list(string)
  description = "AWS services that can be integrated with the organization"
  default = [
    "sso.amazonaws.com",  # IAM Identity Center
  ]
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
    Layer        = "organization"
  }
}
```

---

## Outputs

```hcl
output "organization_id" {
  value       = aws_organizations_organization.main.id
  description = "AWS Organization ID (o-xxxxxxxxxx)"
}

output "organization_arn" {
  value       = aws_organizations_organization.main.arn
  description = "AWS Organization ARN"
}

output "organization_root_id" {
  value       = aws_organizations_organization.main.roots[0].id
  description = "Organization root ID (r-xxxx)"
}

output "management_ou_id" {
  value       = aws_organizations_organizational_unit.management.id
  description = "Management OU ID"
}

output "proprietary_workloads_ou_id" {
  value       = aws_organizations_organizational_unit.proprietary_workloads.id
  description = "Proprietary Workloads OU ID"
}

output "proprietary_signals_account_id" {
  value       = aws_organizations_account.proprietary_signals.id
  description = "Proprietary Signals account ID"
}

output "proprietary_signals_account_arn" {
  value       = aws_organizations_account.proprietary_signals.arn
  description = "Proprietary Signals account ARN"
}
```

**Usage:**
- `sso/` layer: Assign SSO permission sets to accounts
- `scp/` layer: Attach SCPs to OUs (future)
- Cross-account access: Assume role into member accounts

---

## Authentication & Permissions

### Required AWS Permissions

**For imports and account creation:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "organizations:DescribeOrganization",
        "organizations:ListRoots",
        "organizations:ListOrganizationalUnitsForParent",
        "organizations:ListAccounts",
        "organizations:DescribeOrganizationalUnit",
        "organizations:DescribeAccount",
        "organizations:CreateAccount",
        "organizations:TagResource",
        "organizations:UntagResource"
      ],
      "Resource": "*"
    }
  ]
}
```

**Authentication Options:**
1. Root user (not recommended for regular use)
2. IAM admin user with Organizations permissions
3. SSO admin user (after SSO configured)

### Provider Configuration

```hcl
# provider.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "management-sso"  # or "management-admin"

  default_tags {
    tags = {
      Organization = "Noise2Signal LLC"
      ManagedBy    = "terraform"
      Layer        = "organization"
    }
  }
}
```

---

## State Management

### Current: Local State

```bash
# State file location
organization/terraform.tfstate
```

**Security:**
- Contains sensitive data (account IDs, ARNs)
- NEVER commit to Git
- Backup before every `terraform apply`

**Backup command:**
```bash
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
```

### Future: Remote State

Remote state (S3 + DynamoDB) deferred to FUTURE_CONCERNS.md.

When migrating to remote state:
1. Create S3 bucket + DynamoDB table in management account
2. Uncomment `backend.tf`
3. Run `terraform init -migrate-state`

---

## Accessing Member Accounts

### Via OrganizationAccountAccessRole

AWS automatically creates `OrganizationAccountAccessRole` in member accounts created via Organizations:

```bash
# Get account ID from Terraform
ACCOUNT_ID=$(terraform output -raw proprietary_signals_account_id)

# Assume role
aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole" \
  --role-session-name "management-access"

# Use returned credentials (AccessKeyId, SecretAccessKey, SessionToken)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# Verify access
aws sts get-caller-identity
```

**Use this for:**
- Initial account setup
- Emergency access
- Deploying IAM roles in member account

**Don't use this for:**
- Regular daily access (use SSO instead)
- Long-term access (session expires after 1 hour)

### Via IAM Identity Center (Recommended)

After SSO is configured in the `sso/` layer:
1. Assign your SSO user to Proprietary Signals account
2. Grant AdministratorAccess permission set
3. Login via SSO portal: `aws sso login --profile proprietary-signals`

---

## Post-Deployment Tasks

### After Phase 1 (Import)

1. **Verify state file:** `ls -l terraform.tfstate`
2. **Backup state:** `cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)`
3. **Commit code:** `git add *.tf && git commit -m "Import organization structure"`

### After Phase 2 (Account Creation)

1. **Record account ID:**
   ```bash
   terraform output proprietary_signals_account_id > ../proprietary_signals_account_id.txt
   ```

2. **Set root user password:**
   - Use "Forgot Password" flow
   - Enable MFA (virtual or hardware token)
   - Store credentials securely (password manager)

3. **Test cross-account access:**
   ```bash
   # Via OrganizationAccountAccessRole
   aws sts assume-role --role-arn arn:aws:iam::<account-id>:role/OrganizationAccountAccessRole --role-session-name test
   ```

4. **Configure SSO access (next layer):**
   - Deploy `sso/` layer
   - Assign SSO users to new account
   - Test SSO login to new account

---

## Troubleshooting

### Import Errors

**Error: Resource not found**
- Verify resource exists in AWS Console
- Check resource ID is correct
- Ensure AWS CLI is authenticated correctly

**Error: Resource already managed**
- Resource may already be in state file
- Run `terraform state list` to check
- If duplicate, remove with `terraform state rm <resource>`

### Account Creation Failures

**Error: Email already in use**
- Email must be unique across all AWS accounts globally
- Use email aliases: `user+alias@domain.com`
- Cannot reuse email from closed accounts for 90 days

**Error: Account creation timeout**
- Account creation can take up to 15 minutes
- Check AWS Console Organizations page for status
- If stuck, contact AWS Support

**Error: Service limit exceeded**
- Default limit: 10 accounts per organization
- Request limit increase via AWS Support
- Limit increase typically approved within 1 business day

---

## Security Considerations

### Account Separation

**Management account should NEVER:**
- Host workload resources (websites, databases, applications)
- Store application data
- Run production services

**Management account should ONLY:**
- Manage organization structure
- Provide IAM Identity Center for human access
- Centralize billing

### Root User Security

**For all accounts:**
- Use strong, unique passwords
- Enable MFA (hardware token preferred)
- Store credentials securely offline
- Use root only for break-glass scenarios

**Don't use root user for:**
- Daily operations (use SSO/IAM users)
- API access (use IAM roles)
- Programmatic access (use temporary credentials)

---

## Next Steps

### After Completing Organization Layer

1. **Deploy SSO Layer:**
   - Configure IAM Identity Center
   - Create permission sets
   - Assign users to accounts
   - See: [../sso/CLAUDE.md](../sso/CLAUDE.md)

2. **Configure Workload Repository:**
   - Set up `iac-aws-proprietary` repository
   - Deploy Route53, S3, CloudFront infrastructure
   - See: Main [../CLAUDE.md](../CLAUDE.md) Phase 3

3. **Consider Future Enhancements:**
   - Service Control Policies (see FUTURE_CONCERNS.md)
   - Remote state backend (see FUTURE_CONCERNS.md)
   - Additional accounts (see FUTURE_CONCERNS.md)

---

## References

### Documentation
- [Main Architecture](../CLAUDE.md) - Overall AWS organization architecture
- [SSO Layer](../sso/CLAUDE.md) - IAM Identity Center configuration
- [Future Concerns](../FUTURE_CONCERNS.md) - Deferred features

### AWS Documentation
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [Creating Member Accounts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_create.html)
- [Organizational Units](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_ous.html)
- [Accessing Member Accounts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html)

### Terraform Documentation
- [aws_organizations_organization](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization)
- [aws_organizations_organizational_unit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit)
- [aws_organizations_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account)

---

**Layer:** 0 (Organization)
**Account:** Noise2Signal LLC (Management)
**Status:** Phase 1 (Import) → Phase 2 (Create Account)
**Last Updated:** 2026-01-27
