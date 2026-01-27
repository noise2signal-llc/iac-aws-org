# SSO Layer - IAM Identity Center

## Purpose

The **SSO layer** configures AWS IAM Identity Center (formerly AWS SSO) to provide centralized authentication and access management for human users across all AWS accounts in the organization.

**Layer 1** - Deployed after organization layer

**Design Goal:** Replace root user access with SSO for all human operations (except break-glass scenarios).

---

## Current State

### Resources Already Created (Need Import)

The following resources were created manually in the AWS console and need to be imported into Terraform:

**IAM Identity Center:**
- ✓ IAM Identity Center enabled in us-east-1
- ✓ AWS-managed directory configured
- ✓ Centralized root access management enabled

**Status:** ✓ Exists, needs import (if you've created users or permission sets)

### Resources to Create via Terraform

**Next Steps:**
- → AdministratorAccess permission set (or import if already created)
- → Assign LLC member user to management account
- → Assign LLC member user to Proprietary Signals account (after account created)

**Future (Deferred):**
- PowerUserAccess permission set (see FUTURE_CONCERNS.md)
- ReadOnlyAccess permission set (see FUTURE_CONCERNS.md)
- Additional users (see FUTURE_CONCERNS.md)
- MFA enforcement policies (see FUTURE_CONCERNS.md)

---

## Resources Managed by This Layer

### IAM Identity Center Instance

IAM Identity Center is a singleton resource - one instance per organization. When enabled manually, it exists but may not be managed by Terraform initially.

```hcl
# Data source to reference existing IAM Identity Center instance
data "aws_ssoadmin_instances" "main" {}

# Outputs for use in other resources
locals {
  sso_instance_arn   = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  identity_store_id  = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}
```

**Status:** ✓ Exists (enabled manually), referenced via data source

**Key Points:**
- No Terraform resource needed for the instance itself
- Reference via data source for permission sets and assignments
- Region: us-east-1 (IAM Identity Center is regional, but manages global access)

### Permission Sets

Permission sets define what users can do in assigned accounts. They're like reusable IAM roles that apply across multiple accounts.

**AdministratorAccess Permission Set:**

```hcl
resource "aws_ssoadmin_permission_set" "administrator" {
  name             = "AdministratorAccess"
  description      = "Full administrative access to AWS services and resources"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"  # 8 hours

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}

# Attach AWS-managed AdministratorAccess policy
resource "aws_ssoadmin_managed_policy_attachment" "administrator" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

**Status:** → To create (or import if already exists)

**To check if exists:**
```bash
# List existing permission sets
aws sso-admin list-permission-sets \
  --instance-arn $(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)

# Describe specific permission set
aws sso-admin describe-permission-set \
  --instance-arn <instance-arn> \
  --permission-set-arn <permission-set-arn>
```

**To import (if exists):**
```bash
# Format: permission_set_arn,instance_arn
terraform import aws_ssoadmin_permission_set.administrator \
  "arn:aws:sso:::permissionSet/<instance-id>/<permission-set-id>,arn:aws:sso:::instance/<instance-id>"
```

### Users

**LLC Member User:**

Users in IAM Identity Center are managed via the identity store. Terraform support for user creation is limited - users are typically created manually.

**Manual user creation** (if not already done):
1. IAM Identity Center console → Users → Add user
2. Enter username (e.g., `llc-member` or your actual name)
3. Enter email address
4. User receives email to set password and configure MFA

**Reference existing user in Terraform:**

```hcl
data "aws_identitystore_user" "llc_member" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.llc_member_username  # e.g., "camden"
    }
  }
}
```

**Status:** User created manually, referenced via data source

### Account Assignments

Assign permission sets to users for specific accounts.

**Assign Administrator to LLC Member in Management Account:**

```hcl
resource "aws_ssoadmin_account_assignment" "llc_member_management" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.llc_member.user_id
  principal_type = "USER"

  target_id   = data.aws_organizations_organization.main.master_account_id
  target_type = "AWS_ACCOUNT"
}
```

**Status:** → To create

**Assign Administrator to LLC Member in Proprietary Signals Account:**

```hcl
resource "aws_ssoadmin_account_assignment" "llc_member_proprietary_signals" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.llc_member.user_id
  principal_type = "USER"

  target_id   = var.proprietary_signals_account_id  # From organization layer
  target_type = "AWS_ACCOUNT"
}
```

**Status:** → To create (after Proprietary Signals account exists)

---

## Deployment Phases

### Phase 1: Import/Reference Existing Resources

**Prerequisites:**
- IAM Identity Center enabled (✓ done)
- At least one user created (LLC member)

**Step 1: Initialize Terraform**

```bash
cd sso/
terraform init
```

**Step 2: Create Data Sources Configuration**

Create `main.tf` with data sources for existing resources:

```hcl
# Reference IAM Identity Center instance
data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

# Reference organization
data "aws_organizations_organization" "main" {}

# Reference existing user
data "aws_identitystore_user" "llc_member" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.llc_member_username
    }
  }
}
```

**Step 3: Verify Data Sources**

```bash
terraform plan
```

This should successfully read existing resources without creating anything yet.

**Step 4: Check for Existing Permission Sets**

```bash
# Get instance ARN
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)

# List permission sets
aws sso-admin list-permission-sets --instance-arn $INSTANCE_ARN

# If AdministratorAccess exists, import it (next section)
# If not, create it (Phase 2)
```

---

### Phase 2: Create Permission Set and Assignments

**Prerequisites:**
- Phase 1 completed (data sources working)
- LLC member user exists and username known
- Organization layer deployed (management account accessible)

**Step 1: Configure Variables**

Create `terraform.tfvars`:

```hcl
llc_member_username = "camden"  # Your actual SSO username
```

**Important:** Add `*.tfvars` to `.gitignore`

**Step 2: Add Permission Set Resource**

In `main.tf`, add:

```hcl
resource "aws_ssoadmin_permission_set" "administrator" {
  name             = "AdministratorAccess"
  description      = "Full administrative access"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "administrator" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

**Step 3: Add Account Assignment**

```hcl
resource "aws_ssoadmin_account_assignment" "llc_member_management" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.llc_member.user_id
  principal_type = "USER"

  target_id   = data.aws_organizations_organization.main.master_account_id
  target_type = "AWS_ACCOUNT"
}
```

**Step 4: Plan and Apply**

```bash
terraform plan
# Review: Should create 1 permission set, 1 policy attachment, 1 account assignment

terraform apply
```

**Timeline:** 1-2 minutes

**Step 5: Verify SSO Access**

```bash
# Get SSO portal URL
IDENTITY_STORE_ID=$(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text)
echo "SSO Portal: https://${IDENTITY_STORE_ID}.awsapps.com/start"

# Open URL in browser
# Login with your SSO username and password
# Verify management account appears with AdministratorAccess
```

---

### Phase 3: Add Proprietary Signals Account Assignment

**Prerequisites:**
- Phase 2 completed (permission set created, management account assigned)
- Proprietary Signals account created (organization layer Phase 2)
- Account ID known

**Step 1: Update Variables**

Add to `terraform.tfvars`:

```hcl
proprietary_signals_account_id = "123456789012"  # From organization layer output
```

**Step 2: Add Account Assignment**

In `main.tf`, add:

```hcl
resource "aws_ssoadmin_account_assignment" "llc_member_proprietary_signals" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.llc_member.user_id
  principal_type = "USER"

  target_id   = var.proprietary_signals_account_id
  target_type = "AWS_ACCOUNT"
}
```

**Step 3: Apply**

```bash
terraform plan
# Review: Should create 1 new account assignment

terraform apply
```

**Step 4: Verify**

```bash
# Login to SSO portal
# Verify both accounts now appear:
# - Noise2Signal LLC (management)
# - Proprietary Signals
```

---

## Variables

### Required Variables

```hcl
variable "llc_member_username" {
  type        = string
  description = "SSO username for LLC member (must already exist in IAM Identity Center)"
}

variable "proprietary_signals_account_id" {
  type        = string
  description = "Proprietary Signals account ID (from organization layer, only needed for Phase 3)"
  default     = ""  # Optional until account exists
}
```

### Optional Variables

```hcl
variable "session_duration" {
  type        = string
  description = "Session duration for permission sets (ISO 8601 format)"
  default     = "PT8H"  # 8 hours
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
    Layer        = "sso"
  }
}
```

---

## Outputs

```hcl
output "sso_instance_arn" {
  value       = local.sso_instance_arn
  description = "IAM Identity Center instance ARN"
}

output "identity_store_id" {
  value       = local.identity_store_id
  description = "Identity store ID"
}

output "administrator_permission_set_arn" {
  value       = aws_ssoadmin_permission_set.administrator.arn
  description = "AdministratorAccess permission set ARN"
}

output "sso_portal_url" {
  value       = "https://${local.identity_store_id}.awsapps.com/start"
  description = "SSO portal URL for user login (bookmark this)"
}
```

---

## Authentication & Permissions

### Required AWS Permissions

**For Terraform deployment:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sso:*",
        "sso-admin:*",
        "identitystore:*",
        "organizations:DescribeOrganization",
        "organizations:ListAccounts"
      ],
      "Resource": "*"
    }
  ]
}
```

**Authentication Options:**
1. Root user (not recommended for regular use)
2. IAM admin user with SSO permissions
3. SSO admin user (after initial setup)

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
  region  = "us-east-1"  # IAM Identity Center must be in us-east-1
  profile = "management-admin"  # or "management-sso"

  default_tags {
    tags = {
      Organization = "Noise2Signal LLC"
      ManagedBy    = "terraform"
      Layer        = "sso"
    }
  }
}
```

---

## State Management

### Current: Local State

```bash
# State file location
sso/terraform.tfstate
```

**Security:**
- Contains sensitive data (user IDs, account IDs)
- NEVER commit to Git
- Backup before every `terraform apply`

**Backup command:**
```bash
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
```

### Future: Remote State

Remote state (S3 + DynamoDB) deferred to FUTURE_CONCERNS.md.

---

## Configuring AWS CLI with SSO

After SSO is deployed, configure AWS CLI to use SSO for authentication.

### Step 1: Configure SSO Profile

```bash
aws configure sso
```

**Prompts and Answers:**
- SSO start URL: `https://<identity-store-id>.awsapps.com/start` (from terraform output)
- SSO region: `us-east-1`
- SSO registration scopes: (default: `sso:account:access`)
- Account: Select "Noise2Signal LLC" (management account)
- Role: Select "AdministratorAccess"
- CLI default region: `us-east-1`
- CLI default output format: `json`
- CLI profile name: `management-sso`

**Result:** Creates profile in `~/.aws/config`:

```ini
[profile management-sso]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start
sso_region = us-east-1
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1
output = json
```

### Step 2: Login

```bash
aws sso login --profile management-sso
```

**Result:** Opens browser, authenticates via SSO portal, caches temporary credentials

### Step 3: Use Profile

```bash
# Test access
aws sts get-caller-identity --profile management-sso

# Use with Terraform
export AWS_PROFILE=management-sso
terraform plan

# Or specify in provider.tf
provider "aws" {
  profile = "management-sso"
}
```

**Session duration:** 8 hours (from permission set configuration)

**Re-authentication:** Run `aws sso login --profile management-sso` when session expires

### Step 4: Configure Proprietary Signals Profile

After Proprietary Signals account is created and assigned:

```bash
aws configure sso
# SSO start URL: (same as above)
# Account: Select "Proprietary Signals"
# Role: AdministratorAccess
# Profile name: proprietary-signals-sso

# Login
aws sso login --profile proprietary-signals-sso

# Test
aws sts get-caller-identity --profile proprietary-signals-sso
```

---

## Post-Deployment Tasks

### After Phase 1 (Data Sources)

1. **Verify state:** `ls -l terraform.tfstate`
2. **Backup state:** `cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)`
3. **Commit code:** `git add *.tf && git commit -m "Add SSO data sources"`

### After Phase 2 (Permission Set)

1. **Record SSO portal URL:**
   ```bash
   terraform output sso_portal_url
   # Bookmark this URL
   ```

2. **Test SSO login:**
   - Open portal URL
   - Login with username + password + MFA
   - Verify management account appears
   - Test access to management console

3. **Configure AWS CLI:**
   - Run `aws configure sso` (see above)
   - Login: `aws sso login --profile management-sso`
   - Test: `aws sts get-caller-identity --profile management-sso`

4. **Update Terraform provider:**
   - Change `profile = "management-admin"` to `profile = "management-sso"` in provider.tf
   - Use SSO for all future Terraform operations

### After Phase 3 (Proprietary Signals)

1. **Test access to new account:**
   - Login to SSO portal
   - Verify Proprietary Signals appears
   - Test console access

2. **Configure AWS CLI profile:**
   - Run `aws configure sso` for Proprietary Signals account
   - Login: `aws sso login --profile proprietary-signals-sso`

---

## Creating Additional SSO Users

### Step 1: Create User (Manual)

**Via AWS Console:**
1. IAM Identity Center → Users → Add user
2. Username: (user's name or username)
3. Email: (user's email)
4. First/Last name
5. Send email invitation

**Via AWS CLI:**
```bash
# Get identity store ID
IDENTITY_STORE_ID=$(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text)

# Create user
aws identitystore create-user \
  --identity-store-id $IDENTITY_STORE_ID \
  --user-name "john-doe" \
  --display-name "John Doe" \
  --name Formatted=string,FamilyName="Doe",GivenName="John" \
  --emails Value=john@example.com,Type=work,Primary=true
```

### Step 2: Add Account Assignment (Terraform)

In `main.tf`:

```hcl
data "aws_identitystore_user" "john_doe" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "john-doe"
    }
  }
}

resource "aws_ssoadmin_account_assignment" "john_doe_management" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.administrator.arn

  principal_id   = data.aws_identitystore_user.john_doe.user_id
  principal_type = "USER"

  target_id   = data.aws_organizations_organization.main.master_account_id
  target_type = "AWS_ACCOUNT"
}
```

Apply:
```bash
terraform apply
```

**Note:** Creating additional permission sets (PowerUser, ReadOnly) is deferred to FUTURE_CONCERNS.md.

---

## Troubleshooting

### Error: Identity Center Not Available in Region

**Message:** `InvalidRequestException: Identity Center is not available in this region`

**Resolution:** Deploy in `us-east-1` region

### Error: User Not Found

**Message:** `ResourceNotFoundException: User not found`

**Cause:** User doesn't exist or incorrect username

**Resolution:**
```bash
# List all users
IDENTITY_STORE_ID=$(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text)
aws identitystore list-users --identity-store-id $IDENTITY_STORE_ID

# Verify username matches exactly (case-sensitive)
```

### Error: Permission Set Already Exists

**Message:** `ConflictException: Permission set with this name already exists`

**Resolution:** Import existing permission set or use a different name:
```bash
# List permission sets
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
aws sso-admin list-permission-sets --instance-arn $INSTANCE_ARN

# Import existing one
terraform import aws_ssoadmin_permission_set.administrator "<permission-set-arn>,<instance-arn>"
```

### SSO Login Fails

**Symptoms:** Cannot login to SSO portal, "incorrect username or password"

**Checklist:**
1. User exists and is active (check IAM Identity Center console)
2. Password is correct (try password reset)
3. MFA is configured correctly
4. SSO portal URL is correct

**Resolution:**
```bash
# Verify user status
aws identitystore list-users --identity-store-id $IDENTITY_STORE_ID --filters AttributePath=UserName,AttributeValue=<username>

# Reset password via console if needed
```

### AWS CLI SSO Session Expired

**Message:** `Token has expired`

**Resolution:**
```bash
# Re-login
aws sso login --profile management-sso

# Session will last 8 hours
```

---

## Security Considerations

### MFA Enforcement

**Recommendation:** Enable MFA for all users

**Configuration** (manual, limited Terraform support):
1. IAM Identity Center console → Settings → Authentication
2. Configure MFA: "Every time they sign in (always-on)"
3. Allowed methods: Authenticator app, Security key

**Best practices:**
- Hardware security keys (YubiKey) for admin users
- Authenticator apps (Google Authenticator, Authy) acceptable for all users
- SMS not recommended (can be intercepted)

### Session Duration

**Current:** 8 hours (balance between security and usability)

**Considerations:**
- Shorter duration = more secure, more re-authentication
- Longer duration = less secure, more convenience
- For highly sensitive operations: Consider 1-2 hour sessions

### Least Privilege

**Current approach:**
- LLC member: AdministratorAccess to all accounts

**Future approach** (see FUTURE_CONCERNS.md):
- Additional users: PowerUserAccess (no IAM/Organizations)
- Auditors: ReadOnlyAccess
- Principle of least privilege: Only grant minimum permissions needed

### Break-Glass Access

**Root user still available:**
- Use only when SSO is down or misconfigured
- Keep root credentials secure offline
- Test root access quarterly
- Enable MFA on root user

---

## Next Steps

### After Completing SSO Layer

1. **Update all AWS CLI profiles to use SSO:**
   - Replace static credentials with SSO profiles
   - Update Terraform provider.tf to use SSO profile
   - Remove old access keys (if any)

2. **Deploy Proprietary Signals account** (if not done):
   - Return to organization layer
   - Create Proprietary Signals account
   - Return to SSO layer Phase 3 to assign access

3. **Set up workload repository:**
   - Create `iac-aws-proprietary` repository
   - Configure to use SSO for authentication
   - Deploy workload infrastructure (Route53, S3, CloudFront)

4. **Consider future enhancements** (see FUTURE_CONCERNS.md):
   - Additional permission sets (PowerUser, ReadOnly)
   - Additional users
   - MFA enforcement policies
   - External identity provider integration (Google Workspace, Okta)

---

## Cost Considerations

**IAM Identity Center:** Free (no charge for users, permission sets, or assignments)

**Billing impact:** $0/month

---

## References

### Documentation
- [Main Architecture](../CLAUDE.md) - Overall AWS organization architecture
- [Organization Layer](../organization/CLAUDE.md) - Previous layer
- [Future Concerns](../FUTURE_CONCERNS.md) - Deferred features

### AWS Documentation
- [IAM Identity Center User Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Permission Sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)
- [AWS CLI with SSO](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [Configuring MFA](https://docs.aws.amazon.com/singlesignon/latest/userguide/enable-mfa.html)

### Terraform Documentation
- [aws_ssoadmin_permission_set](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set)
- [aws_ssoadmin_account_assignment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment)
- [aws_identitystore_user (data source)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_user)

---

**Layer:** 1 (SSO)
**Account:** Noise2Signal LLC (Management)
**Status:** Phase 1 (Reference) → Phase 2 (Create) → Phase 3 (Assign Proprietary Signals)
**Last Updated:** 2026-01-27
