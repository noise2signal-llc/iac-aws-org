# Management Account - SSO Layer (IAM Identity Center)

## Purpose

The **SSO layer** configures AWS IAM Identity Center (formerly AWS SSO) to provide centralized authentication and access management for human users across all AWS accounts in the organization.

**This is Layer 1** - deployed after the organization layer.

---

## Responsibilities

1. **Enable IAM Identity Center** in us-east-1 region
2. **Create permission sets** (AdministratorAccess, PowerUserAccess, ReadOnlyAccess)
3. **Create SSO users** (starting with boss user)
4. **Assign permissions** to accounts (management, whollyowned)
5. **Configure MFA enforcement** (future enhancement)
6. **Output SSO portal URL** for user login

**Design Goal**: Replace root user access with SSO for all human operations (except break-glass scenarios).

---

## Resources Created

### IAM Identity Center Instance

IAM Identity Center is automatically enabled when you create the first resource. AWS Organizations integration is automatic (one Identity Center per organization).

**Region**: `us-east-1` (recommended for all global services)

### Permission Sets

Permission sets define what users can do in assigned accounts. Think of them as reusable IAM roles.

```hcl
# AdministratorAccess - Full admin (boss only)
resource "aws_ssoadmin_permission_set" "administrator" {
  name             = "AdministratorAccess"
  description      = "Full administrative access to AWS services and resources"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT8H"  # 8 hours

  tags = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    ManagedBy    = "terraform"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "administrator" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# PowerUserAccess - Developers (no IAM permissions)
resource "aws_ssoadmin_permission_set" "power_user" {
  name             = "PowerUserAccess"
  description      = "Full access to AWS services except IAM and Organizations"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT8H"

  tags = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    ManagedBy    = "terraform"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "power_user" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.power_user.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# ReadOnlyAccess - Auditors, finance team
resource "aws_ssoadmin_permission_set" "read_only" {
  name             = "ReadOnlyAccess"
  description      = "Read-only access to AWS services and resources"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT8H"

  tags = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    ManagedBy    = "terraform"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

**Session Duration**: 8 hours (users must re-authenticate after 8 hours)

### Users

**Initial User**: Boss (created manually in AWS console initially, automated later)

**Note**: Terraform AWS provider does not fully support user/group creation in IAM Identity Center. Users must be created manually in the AWS console or via AWS CLI initially. Account assignments can be managed via Terraform.

**Manual User Creation** (one-time):
1. Open IAM Identity Center console in management account
2. Go to "Users" → "Add user"
3. Enter username (e.g., `boss`), email, first/last name
4. User receives email with setup link
5. User sets password and configures MFA

**Future Enhancement**: Use SCIM integration with external identity provider (Google Workspace, Okta, etc.)

### Account Assignments

Assign permission sets to users for specific accounts:

```hcl
# Data source: Get IAM Identity Center instance
data "aws_ssoadmin_instances" "main" {}

# Data source: Get whollyowned account ID (from organization layer)
data "aws_organizations_organization" "main" {}

data "aws_organizations_account" "whollyowned" {
  # Filter by account name or use output from organization layer
  # For now, assume we know the account ID (from organization layer output)
}

# Data source: Get SSO user (manual creation)
data "aws_identitystore_user" "boss" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.boss_username  # e.g., "boss"
    }
  }
}

# Assign AdministratorAccess to boss in management account
resource "aws_ssoadmin_account_assignment" "boss_management" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.boss.user_id
  principal_type = "USER"

  target_id   = data.aws_organizations_organization.main.master_account_id
  target_type = "AWS_ACCOUNT"
}

# Assign AdministratorAccess to boss in whollyowned account
resource "aws_ssoadmin_account_assignment" "boss_whollyowned" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.boss.user_id
  principal_type = "USER"

  target_id   = var.whollyowned_account_id  # From organization layer output
  target_type = "AWS_ACCOUNT"
}
```

**Result**: Boss can log into SSO portal and access both management and whollyowned accounts with full admin permissions.

---

## Variables

### Required Variables

```hcl
variable "whollyowned_account_id" {
  type        = string
  description = "Whollyowned account ID (from organization layer output)"
  # Set in terraform.tfvars or use output reference
}

variable "boss_username" {
  type        = string
  description = "SSO username for boss user"
  default     = "boss"
}
```

### Optional Variables

```hcl
variable "session_duration" {
  type        = string
  description = "Session duration for permission sets (ISO 8601 format)"
  default     = "PT8H"  # 8 hours
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
output "sso_instance_arn" {
  value       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  description = "IAM Identity Center instance ARN"
}

output "identity_store_id" {
  value       = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
  description = "Identity store ID"
}

output "administrator_permission_set_arn" {
  value       = aws_ssoadmin_permission_set.administrator.arn
  description = "AdministratorAccess permission set ARN"
}

output "power_user_permission_set_arn" {
  value       = aws_ssoadmin_permission_set.power_user.arn
  description = "PowerUserAccess permission set ARN"
}

output "read_only_permission_set_arn" {
  value       = aws_ssoadmin_permission_set.read_only.arn
  description = "ReadOnlyAccess permission set ARN"
}

output "sso_portal_url" {
  value       = "https://${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}.awsapps.com/start"
  description = "SSO portal URL for user login"
}
```

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
        "sso:*",
        "sso-directory:*",
        "identitystore:*",
        "organizations:DescribeOrganization",
        "organizations:ListAccounts",
        "ds:AuthorizeApplication",
        "ds:UnauthorizeApplication"
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
  region = "us-east-1"  # IAM Identity Center must be in us-east-1
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
#     key            = "management/sso.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-management-lock"
#     encrypt        = true
#   }
# }
```

**After tfstate-backend layer**: Uncomment and migrate to S3

---

## Deployment

### Prerequisites
1. Organization layer deployed (whollyowned account exists)
2. Whollyowned account ID known

### Step 1: Create Boss User (Manual, One-Time)

**Via AWS Console**:
1. Log in to management account (root user or admin)
2. Navigate to IAM Identity Center console (us-east-1)
3. Choose "Users" → "Add user"
4. Enter details:
   - Username: `boss`
   - Email: `boss@noise2signal.com` (use actual email)
   - First name: (boss's first name)
   - Last name: (boss's last name)
5. Click "Add user"
6. User receives email with setup link
7. User clicks link, sets password, configures MFA

**Via AWS CLI** (alternative):
```bash
# Get identity store ID
IDENTITY_STORE_ID=$(aws sso-admin list-instances \
  --query 'Instances[0].IdentityStoreId' \
  --output text)

# Create user
aws identitystore create-user \
  --identity-store-id $IDENTITY_STORE_ID \
  --user-name boss \
  --display-name "Boss Name" \
  --name Formatted=string,FamilyName=LastName,GivenName=FirstName \
  --emails Value=boss@noise2signal.com,Type=work,Primary=true
```

### Step 2: Create terraform.tfvars
```hcl
# management/sso/terraform.tfvars
whollyowned_account_id = "123456789012"  # From organization layer output
boss_username           = "boss"
```

### Step 3: Initialize Terraform
```bash
cd management/sso
terraform init
```

### Step 4: Review Plan
```bash
terraform plan
```

**Expected Resources**:
- 3 permission sets (Administrator, PowerUser, ReadOnly)
- 3 managed policy attachments
- 2 account assignments (boss → management, boss → whollyowned)

### Step 5: Apply
```bash
terraform apply
```

**Timeline**: ~1-2 minutes

### Step 6: Verify

**Get SSO portal URL**:
```bash
terraform output sso_portal_url
# Example: https://d-xxxxxxxxxx.awsapps.com/start
```

**Test SSO login**:
1. Open SSO portal URL in browser
2. Log in as boss user (with password + MFA)
3. Verify both accounts appear (management, whollyowned)
4. Click on management account → AdministratorAccess → "Management console"
5. Verify you're logged into management account with admin access

---

## Configuring AWS CLI with SSO

### Step 1: Configure SSO Profile

```bash
aws configure sso
```

**Prompts**:
- SSO start URL: `https://d-xxxxxxxxxx.awsapps.com/start`
- SSO region: `us-east-1`
- SSO registration scopes: (leave default: `sso:account:access`)
- Select account: Choose management or whollyowned
- Select role: Choose AdministratorAccess
- CLI default region: `us-east-1`
- CLI default output format: `json`
- CLI profile name: `management-admin` or `whollyowned-admin`

**Result**: Creates profile in `~/.aws/config`:
```ini
[profile management-admin]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start
sso_region = us-east-1
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1
output = json
```

### Step 2: Log In
```bash
aws sso login --profile management-admin
```

**Result**: Opens browser, prompts for SSO login, caches credentials

### Step 3: Use Profile
```bash
# Test access
aws sts get-caller-identity --profile management-admin

# Use in Terraform
export AWS_PROFILE=management-admin
terraform plan
```

**Session Duration**: 8 hours (from permission set configuration)

---

## Post-Deployment Tasks

### 1. Record SSO Portal URL
```bash
terraform output sso_portal_url
# Bookmark this URL - users will use it to log in
```

### 2. Configure MFA Enforcement (Recommended)

**Via Console** (Terraform support limited):
1. IAM Identity Center console → "Settings" → "Authentication"
2. Configure MFA settings:
   - Enable "Every time they sign in (MFA always-on)"
   - Allowed authenticator types: Authenticator app, Security key
3. Save changes

**Result**: Users must configure MFA on next login

### 3. Test Break-Glass Access

**Verify root user still works**:
1. Log out of SSO
2. Log in to management account as root user
3. Verify access
4. Log out and return to SSO

**Root user should only be used for**:
- Break-glass scenarios (SSO is down)
- Billing/payment method changes
- Account-level changes (enable/disable regions, close account)

### 4. Proceed to Next Layer
**Next**: Deploy `management/scp` layer (Service Control Policies)

---

## Adding New Users

### Step 1: Create User (Manual)
Same process as boss user creation (console or CLI)

### Step 2: Add Account Assignment (Terraform)

```hcl
# In main.tf
data "aws_identitystore_user" "developer1" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "developer1"
    }
  }
}

# Assign PowerUserAccess to developer1 in whollyowned account
resource "aws_ssoadmin_account_assignment" "developer1_whollyowned" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.power_user.arn

  principal_id   = data.aws_identitystore_user.developer1.user_id
  principal_type = "USER"

  target_id   = var.whollyowned_account_id
  target_type = "AWS_ACCOUNT"
}
```

### Step 3: Apply
```bash
terraform apply
```

**Result**: New user can log into SSO portal and access whollyowned account with PowerUser permissions

---

## Troubleshooting

### Error: Identity Center Not Available in Region
**Message**: `InvalidRequestException: Identity Center is not available in this region`

**Cause**: IAM Identity Center only available in certain regions

**Resolution**: Deploy in `us-east-1` (recommended for global services)

### Error: User Not Found
**Message**: `ResourceNotFoundException: User not found`

**Cause**: User not created yet, or incorrect username

**Resolution**:
1. Verify user exists: `aws identitystore list-users --identity-store-id <ID>`
2. Check username spelling in `terraform.tfvars`

### Error: Cannot Enable Identity Center
**Message**: `ConflictException: Organization does not have all features enabled`

**Cause**: Organization not fully enabled (consolidated billing only)

**Resolution**: Enable all features in organization layer: `feature_set = "ALL"`

### SSO Login Fails
**Cause**: User credentials incorrect, MFA not configured, account assignment missing

**Resolution**:
1. Verify user exists and is active
2. Reset user password if needed
3. Verify account assignment exists: `aws sso-admin list-account-assignments`

---

## Cost Considerations

**IAM Identity Center**: Free (no charge for users, permission sets, or account assignments)

**Billing Impact**: None (organization-level service)

---

## Security Considerations

### Least Privilege
- **AdministratorAccess**: Only for boss and break-glass scenarios
- **PowerUserAccess**: For developers (no IAM/Organizations access)
- **ReadOnlyAccess**: For auditors, finance team

### MFA Enforcement
- **Highly recommended**: Enable MFA always-on
- **Hardware tokens**: Preferred for admin users
- **Authenticator apps**: Acceptable for all users

### Session Duration
- **8 hours**: Balance between security and usability
- **Consider shorter**: For highly privileged accounts (1-2 hours)

### Audit Trail
- **CloudTrail**: All SSO actions logged (login, assume role, etc.)
- **Monitor anomalies**: Failed login attempts, unusual access patterns

---

## References

### Related Layers
- [../CLAUDE.md](../CLAUDE.md) - Management account overview
- [../organization/CLAUDE.md](../organization/CLAUDE.md) - Previous layer
- [../scp/CLAUDE.md](../scp/CLAUDE.md) - Next layer

### AWS Documentation
- [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Permission Sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)
- [AWS CLI with SSO](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)

---

**Layer**: 1 (SSO)
**Account**: noise2signal-llc-management
**Last Updated**: 2026-01-26
