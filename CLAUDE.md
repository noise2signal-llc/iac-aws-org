# Noise2Signal LLC - AWS Organizations Infrastructure

## Executive Summary

This repository manages the **AWS Organization infrastructure** for Noise2Signal LLC using Terraform. The architecture uses a **single repository with multiple Terraform layers** to manage the management account's governance resources and organizational structure.

**Key Design Principles:**
- **Account Isolation**: Separate AWS accounts for management vs workloads
- **Separation of Concerns**: Infrastructure organized into discrete Terraform layers
- **Security**: Minimal management account footprint, workloads in separate accounts
- **Cost Transparency**: Cost allocation tags for all resources
- **Single Human Operator**: Manual Terraform apply by LLC member via AWS CLI

**Current Scope**: Management account governance only. Workload infrastructure (websites) managed in separate repository.

---

## AWS Organization Structure

### Account Hierarchy

```
Root (Organization Root)
├── Management OU: "Noise2Signal LLC Management"
│   └── Noise2Signal LLC (Management Account) ✓ EXISTS
│       • AWS Organizations ✓
│       • IAM Identity Center ✓
│       • Consolidated billing ✓
│       • Route53 domain: camdenwander.com ✓
│       • Service Control Policies (future)
│
└── Proprietary Workloads OU ✓ EXISTS
    ├── Proprietary Signals (Production Account) → TO CREATE
    │   • Route53 hosted zones
    │   • S3 + CloudFront (static sites)
    │   • ACM certificates
    │
    └── Proprietary Noise (Development Account) → FUTURE
        • Development/staging workloads

Future OUs and accounts documented in FUTURE_CONCERNS.md
```

**Legend:**
- ✓ EXISTS = Already created in AWS console, needs Terraform import
- → TO CREATE = Next step, create via Terraform
- → FUTURE = Deferred to future iteration

### Resource Allocation by Account

**Management Account** (Noise2Signal LLC):
- AWS Organizations (organization root, OUs, member accounts)
- IAM Identity Center (human user SSO, permission sets)
- Route53 Domains (domain registrations only, NOT hosted zones)
- Terraform state (local files for now)

**Proprietary Signals Account** (to be created):
- Route53 hosted zones (for websites)
- S3 buckets (static site content)
- CloudFront distributions
- ACM certificates
- IAM roles (for GitHub Actions deployment)

**Design Principle**: Management account = governance only. All workload resources live in separate accounts.

---

## Repository Structure

```
iac-aws-org/                        # THIS REPOSITORY
├── CLAUDE.md                       # This file
├── FUTURE_CONCERNS.md              # Deferred features
├── README.md                       # Repository overview
├── .gitignore                      # Never commit *.tfstate, *.tfvars
│
├── organization/                   # Layer 0: AWS Organizations
│   ├── CLAUDE.md                   # Layer-specific docs
│   ├── provider.tf                 # AWS provider config
│   ├── main.tf                     # Organization, OUs, accounts
│   ├── variables.tf
│   └── outputs.tf                  # Account IDs, OU IDs
│
├── sso/                            # Layer 1: IAM Identity Center
│   ├── CLAUDE.md
│   ├── provider.tf
│   ├── main.tf                     # Permission sets, users, assignments
│   ├── variables.tf
│   └── outputs.tf                  # SSO ARNs, user IDs
│
├── scp/                            # Layer 2: Service Control Policies (future)
│   └── (deferred to FUTURE_CONCERNS.md)
│
└── modules/                        # Reusable Terraform modules
    └── domain/                     # Route53 domain management
        └── (for domain registrations)
```

**Related Repository** (separate, out of scope for this repo):
- `iac-aws-proprietary/` - Manages Proprietary Signals account workloads (static sites)

---

## Current State

### Manual Steps Already Completed

These resources were created manually in the AWS console and now need to be imported into Terraform:

**2026-01-25: Account Creation**
- AWS account created: "Noise2Signal LLC"
- Billing: Personal credit card
- Root user email configured

**2026-01-25: Domain Transfer**
- Domain `camdenwander.com` transferred from Network Solutions to Route53
- Transfer completed 2026-01-26
- Verified: `whois camdenwander.com` shows AWS as registry

**2026-01-26: Organization Conversion**
- Enabled AWS Organizations (account became management account)
- Created OU: "Noise2Signal LLC Management"
- Moved management account into Management OU
- Created OU: "Proprietary Workloads"

**2026-01-26: IAM Identity Center**
- Enabled IAM Identity Center in us-east-1
- Configured centralized root user access management
- Reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html#id_root-user-access-management

### Resources to Import

The following resources exist in AWS and must be imported into Terraform:

**organization/ layer:**
- AWS Organization (root)
- Management OU (Noise2Signal LLC Management)
- Proprietary Workloads OU
- Management account (Noise2Signal LLC)

**sso/ layer:**
- IAM Identity Center instance
- Permission sets (if any created)
- SSO users (if any created)

**domains/ layer (future):**
- Domain registration: camdenwander.com

---

## Deployment Sequence

### Prerequisites

**Tools Required:**
- AWS CLI v2 (configured with management account credentials)
- Terraform v1.5+
- Git

**AWS Access:**
- Root user credentials OR
- IAM admin user credentials OR
- SSO admin access

---

## Phase 1: Import Existing Resources

Import manually-created resources into Terraform management.

### Step 1: Import Organization Structure

**Directory:** `organization/`

**Import commands:**
```bash
cd organization/

# Initialize Terraform
terraform init

# Import organization root
terraform import aws_organizations_organization.main <organization-id>

# Import Management OU
terraform import aws_organizations_organizational_unit.management <management-ou-id>

# Import Proprietary Workloads OU
terraform import aws_organizations_organizational_unit.proprietary_workloads <proprietary-ou-id>

# Import management account (if not automatically included)
terraform import aws_organizations_account.management <account-id>

# Verify
terraform plan
```

**How to get IDs:**
```bash
# Get organization ID
aws organizations describe-organization --query 'Organization.Id' --output text

# Get root ID
aws organizations list-roots --query 'Roots[0].Id' --output text

# Get OU IDs
aws organizations list-organizational-units-for-parent --parent-id <root-id>

# Get account ID
aws organizations list-accounts --query 'Accounts[?Name==`Noise2Signal LLC`].Id' --output text
```

**Expected output:** `terraform plan` shows no changes (all resources already match)

### Step 2: Import IAM Identity Center

**Directory:** `sso/`

**Import commands:**
```bash
cd ../sso/

# Initialize Terraform
terraform init

# Import IAM Identity Center instance
terraform import aws_ssoadmin_instance.main <instance-arn>

# Get instance ARN
aws sso-admin list-instances --query 'Instances[0].[InstanceArn,IdentityStoreId]' --output text

# Import permission sets (if any created)
terraform import aws_ssoadmin_permission_set.admin <permission-set-arn>

# Import account assignments (if any created)
terraform import aws_ssoadmin_account_assignment.admin_to_management <principal-id>,<principal-type>,<target-id>,<target-type>,<permission-set-arn>,<instance-arn>

# Verify
terraform plan
```

**Expected output:** `terraform plan` shows no changes

### Step 3: Verify State Files

After imports, verify local state files exist:

```bash
ls -l organization/terraform.tfstate
ls -l sso/terraform.tfstate
```

**IMPORTANT:** These files contain sensitive data. Never commit to Git.

**Verify .gitignore:**
```bash
cat .gitignore | grep tfstate
# Should show: *.tfstate, *.tfstate.backup
```

---

## Phase 2: Create New Resources via Terraform

### Step 1: Create Proprietary Signals Account

**Directory:** `organization/`

**Goal:** Create the first workload account under Proprietary Workloads OU.

**Edit main.tf to add:**
```hcl
resource "aws_organizations_account" "proprietary_signals" {
  name              = "Proprietary Signals"
  email             = "aws+proprietary-signals@noise2signal.com"  # UPDATE THIS
  parent_id         = aws_organizations_organizational_unit.proprietary_workloads.id
  close_on_deletion = false

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "proprietary-signals"
    CostCenter   = "proprietary"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}

output "proprietary_signals_account_id" {
  value       = aws_organizations_account.proprietary_signals.id
  description = "Account ID for Proprietary Signals workload account"
}
```

**Apply:**
```bash
cd organization/
terraform plan
# Review: should show 1 new account to create
terraform apply
```

**Save account ID:**
```bash
terraform output proprietary_signals_account_id
# Note this ID for cross-account access setup
```

**Timeline:** Account creation takes 5-15 minutes. You'll receive email at the specified address.

### Step 2: Configure Cross-Account Access (Manual)

After account creation, configure cross-account admin access:

**Option A: IAM Identity Center (Recommended)**
```bash
# In AWS Console:
# 1. Go to IAM Identity Center
# 2. AWS Accounts → Select "Proprietary Signals"
# 3. Assign your SSO user with AdministratorAccess permission set
```

**Option B: IAM Role (Alternative)**
```bash
# In AWS Console:
# 1. Switch to Proprietary Signals account (via AWS Console switch role)
# 2. Create role: OrganizationAccountAccessRole
# 3. Trust policy: Management account ID
# 4. Attach: AdministratorAccess policy
```

### Step 3: Verify Access

```bash
# If using SSO:
aws sso login --profile management
aws sts get-caller-identity

# Test access to new account (update profile):
aws sts get-caller-identity --profile proprietary-signals
```

---

## Phase 3: Next Steps

After creating the Proprietary Signals account:

1. **Set up workload repository** (`iac-aws-proprietary/`)
   - Manages Route53 zones, S3, CloudFront for static sites
   - Separate repository for workload infrastructure

2. **Configure Route53 hosted zone** (in Proprietary Signals account)
   - Create hosted zone for camdenwander.com
   - Update NS records in domain registration (Management account)

3. **Deploy static site infrastructure**
   - S3 bucket + CloudFront
   - ACM certificate
   - DNS records

4. **Consider future enhancements** (see FUTURE_CONCERNS.md)
   - Remote state backends (S3 + DynamoDB)
   - Service Control Policies
   - GitHub OIDC for CI/CD
   - Additional accounts (Proprietary Noise, Client accounts)

---

## Security Architecture

### IAM Identity Center (Current)

**Access Pattern:**
- Human users authenticate via SSO (MFA enforced)
- No long-lived IAM user credentials
- Root user reserved for break-glass only

**Current SSO Configuration:**
- Instance region: us-east-1
- Directory: AWS managed directory
- MFA: Enforced (if configured)

### Root User Security

**Use root user ONLY for:**
- Break-glass emergency access (if SSO fails)
- Billing/payment method changes
- Account closure operations
- Enabling IAM Identity Center centralized root access

**Root user protection:**
- Strong unique password
- MFA enabled (hardware token recommended)
- Credentials stored securely offline

### Service Control Policies (Future)

SCPs deferred to FUTURE_CONCERNS.md. When implemented:
- Management OU: Minimal restrictions (allow governance operations)
- Proprietary Workloads OU: Restrictive (allow-list of services)

---

## Cost Management

### Tagging Strategy

All resources tagged with:

```hcl
tags = {
  Organization = "Noise2Signal LLC"
  Account      = "management"           # or "proprietary-signals"
  CostCenter   = "infrastructure"       # or "proprietary"
  Environment  = "production"
  ManagedBy    = "terraform"
  Layer        = "organization"         # or "sso", "domains"
}
```

### Cost Estimates

**Management Account** (~$1/month):
```
AWS Organizations:           Free
IAM Identity Center:         Free
Route53 domain registration: ~$12/year (~$1/month)
S3 Terraform state:          ~$0.05/month (future)
───────────────────────────────
Total:                       ~$1/month
```

**Proprietary Signals Account** (~$2-6/month per site):
```
Route53 hosted zone:         ~$0.50/month
ACM certificate:             Free
S3 storage (static site):    ~$0.02/GB
CloudFront:                  ~$1-5/month (traffic dependent)
───────────────────────────────
Total:                       ~$2-6/month
```

**Total Organization** (1 domain, 1 site): **~$3-7/month**

### Billing Configuration

**Consolidated billing:** All accounts bill to management account
**Payment method:** Personal credit card on management account
**Cost allocation:** View per-account costs in Cost Explorer (filter by "Linked Account")

---

## Terraform State Management

### Current Approach: Local State

All Terraform layers use local state files:

```
organization/terraform.tfstate      # Organizations, OUs, accounts
sso/terraform.tfstate              # IAM Identity Center resources
```

**Critical Security:**
- State files contain sensitive data (account IDs, ARNs)
- NEVER commit state files to Git
- Backup state files securely offline
- Verify .gitignore includes: `*.tfstate`, `*.tfstate.backup`

**State file handling:**
```bash
# Backup before major changes
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# Store backups securely (outside Git)
# Do NOT commit backups to Git
```

### Future: Remote State Backend

Remote state (S3 + DynamoDB) deferred to FUTURE_CONCERNS.md.

**Benefits of migration (future):**
- State locking (prevent concurrent modifications)
- State encryption at rest
- State versioning (rollback capability)
- Team collaboration (if needed)

**Current decision:** Local state sufficient for single-operator manual deployment.

---

## Disaster Recovery

### Organization Recovery

**If organization is misconfigured:**
1. Use root user to access AWS Console
2. Review AWS Organizations settings
3. Contact AWS Support if needed (identity verification required)

**Protection mechanisms:**
- Organization cannot be deleted while member accounts exist
- Account moves between OUs require explicit parent_id changes in Terraform

### State File Recovery

**If state file is lost or corrupted:**
1. Restore from backup (backup before all terraform apply operations)
2. If no backup: Re-import all resources (see Phase 1)
3. Alternative: Terraform refresh + manual reconciliation

**Prevention:**
- Backup state files before every `terraform apply`
- Store backups in secure location (encrypted USB, password manager)
- Consider S3 remote backend migration (see FUTURE_CONCERNS.md)

### SSO Recovery

**If SSO is broken:**
1. Use root user to access IAM Identity Center console
2. Recreate or fix configuration
3. Re-import into Terraform if needed

**Break-glass access:** Root user credentials always bypass SSO

---

## Development Workflow

### Making Changes

**Standard workflow for infrastructure changes:**

```bash
# 1. Pull latest code
git pull origin main

# 2. Navigate to layer
cd organization/  # or sso/

# 3. Backup state
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# 4. Make changes to .tf files
vim main.tf

# 5. Plan changes
terraform plan

# 6. Review plan carefully
# Ensure no unexpected deletions or modifications

# 7. Apply changes
terraform apply

# 8. Verify in AWS console
aws organizations list-accounts

# 9. Commit code changes (NOT state files)
git add main.tf
git commit -m "Add Proprietary Signals account"
git push origin main
```

### Git Workflow

**Commit to Git:**
- ✓ All .tf files (main.tf, variables.tf, outputs.tf, provider.tf)
- ✓ Documentation (.md files)
- ✓ .gitignore

**NEVER commit:**
- ✗ terraform.tfstate (sensitive data)
- ✗ terraform.tfstate.backup
- ✗ .terraform/ directory
- ✗ *.tfvars files (if they contain secrets)

---

## Authentication & Access

### AWS CLI Configuration

**For management account access:**

```bash
# Option 1: Root user (not recommended for regular use)
aws configure --profile management-root
# Enter access key, secret key (from root user)

# Option 2: IAM admin user
aws configure --profile management-admin
# Enter IAM user credentials

# Option 3: SSO (recommended after SSO is configured)
aws configure sso --profile management-sso
# SSO start URL: https://<your-sso-portal>.awsapps.com/start
# SSO region: us-east-1
# Account: <management-account-id>
# Role: AdministratorAccess

# Login
aws sso login --profile management-sso

# Use profile
export AWS_PROFILE=management-sso
terraform plan
```

### Terraform Provider Authentication

All provider.tf files use AWS CLI profiles:

```hcl
# organization/provider.tf
provider "aws" {
  region  = "us-east-1"
  profile = "management-sso"  # or "management-admin"

  default_tags {
    tags = {
      Organization = "Noise2Signal LLC"
      ManagedBy    = "terraform"
    }
  }
}
```

**Update profile in provider.tf to match your AWS CLI configuration.**

---

## References

### Layer Documentation
- [organization/CLAUDE.md](./organization/CLAUDE.md) - Organizations, OUs, accounts
- [sso/CLAUDE.md](./sso/CLAUDE.md) - IAM Identity Center configuration
- [FUTURE_CONCERNS.md](./FUTURE_CONCERNS.md) - Deferred features

### AWS Documentation
- [AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Terraform AWS Provider - Organizations](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization)
- [Terraform AWS Provider - SSO Admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set)

### External References
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [AWS Organizations Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices.html)

---

**Document Version:** 4.0 (Simplified Single-Account Focus)
**Last Updated:** 2026-01-27
**Maintainer:** Camden Lindahl, Noise2Signal LLC Member
