# Management Account - Organization Layer

## Purpose

The **organization layer** is the foundation of the AWS Organization structure. It enables AWS Organizations, creates the organizational unit (OU) hierarchy, and provisions member accounts.

**This is Layer 0** - the first infrastructure deployed in the management account.

---

## Responsibilities

1. **Enable AWS Organizations** in the management account
2. **Create OU structure** (Management, Workloads, Clients, Sandbox)
3. **Create nested OUs** (Workloads/Production, Workloads/Development)
4. **Provision member accounts** (`noise2signal-llc-whollyowned`)
5. **Configure consolidated billing** (automatic when org is enabled)
6. **Output account IDs and OU IDs** for use in other layers

---

## Resources Created

### AWS Organization
```hcl
resource "aws_organizations_organization" "org" {
  # Enables AWS Organizations in this account (becomes management account)
  aws_service_access_principals = [
    "sso.amazonaws.com",        # IAM Identity Center
    "cloudtrail.amazonaws.com", # Organization-wide CloudTrail (future)
  ]
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]
  feature_set = "ALL"  # Enable all organization features
}
```

**Key Points**:
- Management account becomes organization root
- Consolidated billing automatically enabled
- Can enable additional AWS services later (CloudTrail, Config, etc.)

### Organizational Units

```hcl
# Root-level OUs
resource "aws_organizations_organizational_unit" "management" {
  name      = "Management"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "clients" {
  name      = "Clients"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.org.roots[0].id
}

# Nested OUs under Workloads
resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = aws_organizations_organizational_unit.workloads.id
}
```

**OU Hierarchy**:
```
Organization Root (r-xxxx)
├── Management OU (ou-xxxx)
│   └── noise2signal-llc-management (management account, auto-placed)
├── Workloads OU (ou-xxxx)
│   ├── Production OU (ou-xxxx)
│   │   └── noise2signal-llc-whollyowned (created below)
│   └── Development OU (ou-xxxx) (empty, future staging accounts)
├── Clients OU (ou-xxxx) (empty, future client accounts)
└── Sandbox OU (ou-xxxx) (empty, future experimentation)
```

**Design Rationale**:
- **Management OU**: Governance and billing account only
- **Workloads/Production**: Production N2S brand websites
- **Workloads/Development**: Future staging/dev environments
- **Clients OU**: Future commissioned work (separate accounts per client)
- **Sandbox OU**: Future experimentation, non-production testing

### Member Accounts

```hcl
resource "aws_organizations_account" "whollyowned" {
  name              = "noise2signal-llc-whollyowned"
  email             = "aws-whollyowned@noise2signal.com"
  parent_id         = aws_organizations_organizational_unit.production.id
  close_on_deletion = false  # Prevent accidental account deletion

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}
```

**Key Points**:
- Account email must be unique (not used by any other AWS account)
- Account is automatically placed in specified OU (Production)
- `close_on_deletion = false`: If Terraform resource is deleted, account is NOT closed (safety)
- Account ID output used by SSO and SCP layers

**Initial Account State**:
- Root user email = `aws-whollyowned@noise2signal.com`
- Root user password: Not set initially (must reset via "Forgot Password")
- No IAM users/roles initially (created in whollyowned/rbac layer)
- Access: Via management account root user (assume OrganizationAccountAccessRole)

---

## Variables

### Required Variables

```hcl
variable "organization_name" {
  type        = string
  description = "Name of the AWS Organization"
  default     = "noise2signal-llc"
}

variable "whollyowned_account_email" {
  type        = string
  description = "Email address for whollyowned account (must be unique)"
  # Set in terraform.tfvars: "aws-whollyowned@noise2signal.com"
}
```

### Optional Variables

```hcl
variable "aws_service_access_principals" {
  type        = list(string)
  description = "AWS services that can be integrated with the organization"
  default = [
    "sso.amazonaws.com",
    "cloudtrail.amazonaws.com",
  ]
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}
```

---

## Outputs

```hcl
output "organization_id" {
  value       = aws_organizations_organization.org.id
  description = "AWS Organization ID (e.g., o-xxxxxxxxxx)"
}

output "organization_arn" {
  value       = aws_organizations_organization.org.arn
  description = "AWS Organization ARN"
}

output "organization_root_id" {
  value       = aws_organizations_organization.org.roots[0].id
  description = "Organization root ID (e.g., r-xxxx)"
}

output "management_ou_id" {
  value       = aws_organizations_organizational_unit.management.id
  description = "Management OU ID"
}

output "workloads_ou_id" {
  value       = aws_organizations_organizational_unit.workloads.id
  description = "Workloads OU ID"
}

output "production_ou_id" {
  value       = aws_organizations_organizational_unit.production.id
  description = "Production OU ID (nested under Workloads)"
}

output "development_ou_id" {
  value       = aws_organizations_organizational_unit.development.id
  description = "Development OU ID (nested under Workloads)"
}

output "clients_ou_id" {
  value       = aws_organizations_organizational_unit.clients.id
  description = "Clients OU ID"
}

output "sandbox_ou_id" {
  value       = aws_organizations_organizational_unit.sandbox.id
  description = "Sandbox OU ID"
}

output "whollyowned_account_id" {
  value       = aws_organizations_account.whollyowned.id
  description = "Whollyowned account ID (e.g., 123456789012)"
}

output "whollyowned_account_arn" {
  value       = aws_organizations_account.whollyowned.arn
  description = "Whollyowned account ARN"
}
```

**Usage**: These outputs are used by:
- `sso` layer: Assign permission sets to accounts
- `scp` layer: Attach SCPs to OUs
- Manual operations: Access whollyowned account

---

## Authentication & Permissions

### Initial Deployment
**Authentication**: Root user or admin IAM user in management account

**Required Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "organizations:*",
        "iam:CreateServiceLinkedRole",
        "iam:DeleteServiceLinkedRole"
      ],
      "Resource": "*"
    }
  ]
}
```

**Provider Configuration**:
```hcl
# provider.tf
provider "aws" {
  region = "us-east-1"  # Organizations is a global service, but use us-east-1

  # Initial deployment: Use AWS CLI default profile or environment variables
  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
}
```

---

## State Management

### Initial State (Local)
```hcl
# backend.tf (initially commented out)
# terraform {
#   backend "s3" {
#     bucket         = "n2s-terraform-state-management"
#     key            = "management/organization.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-management-lock"
#     encrypt        = true
#   }
# }
```

**Initial deployment**: Local state file (`terraform.tfstate`)

**After tfstate-backend layer**:
1. Uncomment `backend.tf`
2. Run `terraform init -migrate-state`
3. Confirm state migration to S3
4. Delete local state files

---

## Deployment

### Step 1: Create terraform.tfvars
```hcl
# management/organization/terraform.tfvars
whollyowned_account_email = "aws-whollyowned@noise2signal.com"
```

**Important**: Add `terraform.tfvars` to `.gitignore` (contains email addresses)

### Step 2: Initialize Terraform
```bash
cd management/organization
terraform init
```

### Step 3: Review Plan
```bash
terraform plan
```

**Expected Resources**:
- 1 organization
- 6 organizational units (Management, Workloads, Production, Development, Clients, Sandbox)
- 1 member account (whollyowned)

### Step 4: Apply
```bash
terraform apply
```

**Timeline**: ~2-5 minutes (account creation can take 1-2 minutes)

### Step 5: Verify
```bash
# Verify organization
aws organizations describe-organization

# List OUs
aws organizations list-organizational-units-for-parent \
  --parent-id $(terraform output -raw organization_root_id)

# List accounts
aws organizations list-accounts

# Verify whollyowned account
terraform output whollyowned_account_id
```

---

## Accessing Member Accounts

### Via Management Account Root User

AWS automatically creates `OrganizationAccountAccessRole` in member accounts:

```bash
# Assume role in whollyowned account
aws sts assume-role \
  --role-arn arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/OrganizationAccountAccessRole \
  --role-session-name management-admin

# Export credentials from assume-role output
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# Verify access
aws sts get-caller-identity
```

**Recommendation**: Use this method only for initial bootstrap (deploying whollyowned/rbac layer). After SSO is configured, use SSO for all human access.

---

## Post-Deployment Tasks

### 1. Record Account IDs
```bash
# Save these for later use
terraform output whollyowned_account_id  # e.g., 123456789012
terraform output management_ou_id        # e.g., ou-xxxx-xxxxxxxx
terraform output production_ou_id        # e.g., ou-xxxx-xxxxxxxx
```

### 2. Secure Root User (Whollyowned Account)
- **Set password**: Use "Forgot Password" flow with account email
- **Enable MFA**: Hardware token recommended
- **Store securely**: Password manager, offline backup

### 3. Proceed to Next Layer
**Next**: Deploy `management/sso` layer (IAM Identity Center)

---

## Maintenance

### Adding New Member Accounts

**Example**: Create a client account

```hcl
# In main.tf
resource "aws_organizations_account" "client_acme" {
  name              = "noise2signal-llc-client-acme"
  email             = "aws-client-acme@noise2signal.com"
  parent_id         = aws_organizations_organizational_unit.clients.id
  close_on_deletion = false

  tags = {
    Organization = "noise2signal-llc"
    Account      = "client-acme"
    CostCenter   = "client-acme"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}

output "client_acme_account_id" {
  value = aws_organizations_account.client_acme.id
}
```

Then: `terraform apply`

### Moving Accounts Between OUs

**Example**: Move whollyowned from Production to Development (for testing)

```hcl
# Change parent_id
resource "aws_organizations_account" "whollyowned" {
  name      = "noise2signal-llc-whollyowned"
  email     = "aws-whollyowned@noise2signal.com"
  parent_id = aws_organizations_organizational_unit.development.id  # Changed
  # ...
}
```

**Impact**: SCPs applied to new OU will affect the account immediately

---

## Troubleshooting

### Error: Organization Already Exists
**Message**: `OrganizationAlreadyExistsException`

**Cause**: Account already has an organization enabled

**Resolution**:
1. Import existing organization: `terraform import aws_organizations_organization.org <org-id>`
2. Or: Manually disable organization (deletes all OUs and member accounts!)

### Error: Email Already in Use
**Message**: `AccountEmailAlreadyExistsException`

**Cause**: Email address used by another AWS account

**Resolution**: Use a different, unique email (e.g., `aws-whollyowned+1@noise2signal.com`)

### Error: Account Limit Reached
**Message**: `ConstraintViolationException: Account limit exceeded`

**Cause**: Default limit is 10 accounts per organization

**Resolution**: Request limit increase via AWS Support (usually approved quickly)

### Error: Cannot Create Organization
**Message**: `AccessDeniedException`

**Cause**: Insufficient IAM permissions

**Resolution**: Ensure you're using root user or IAM user with `organizations:*` permissions

---

## Cost Considerations

**AWS Organizations**: Free
**Member accounts**: Free (no cost to create accounts)

**Billing**: Consolidated billing groups all accounts under management account (organization payer). Individual account costs are tracked separately and can be viewed in Cost Explorer with "Linked Account" dimension.

---

## Security Considerations

### Least Privilege
- **Management account**: Should NOT run workloads (websites, applications)
- **Member accounts**: All workloads run here, isolated from management

### Blast Radius Control
- **OU-level SCPs**: Constrain what member accounts can do
- **Account isolation**: Issue in one account doesn't affect others

### Audit Trail
- **CloudTrail**: Enable organization-wide trail (future enhancement)
- **AWS Config**: Organization-wide compliance monitoring (future)

---

## References

### Related Layers
- [../CLAUDE.md](../CLAUDE.md) - Management account overview
- [../sso/CLAUDE.md](../sso/CLAUDE.md) - Next layer (IAM Identity Center)

### AWS Documentation
- [AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [Creating Member Accounts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_create.html)
- [Organizational Units](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_ous.html)

---

**Layer**: 0 (Organization)
**Account**: noise2signal-llc-management
**Last Updated**: 2026-01-26
