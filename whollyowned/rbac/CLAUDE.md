# Whollyowned Account - RBAC Layer (IAM Roles + OIDC)

## Purpose

The **RBAC layer** creates IAM roles for Terraform execution and the GitHub OIDC provider for secure CI/CD authentication in the **whollyowned account**. This layer enables infrastructure-as-code deployments without long-lived AWS credentials.

**This is Layer 0** - the first layer deployed in the whollyowned account.

---

## Responsibilities

1. **Create GitHub OIDC provider** (federated authentication from GitHub Actions)
2. **Create Terraform execution roles**:
   - `tfstate-terraform-role` (state backend management)
   - `domains-terraform-role` (Route53 zones + ACM certificates)
   - `sites-terraform-role` (S3 buckets + CloudFront + DNS records)
3. **Configure trust policies** (all roles trust GitHub OIDC provider)
4. **Attach IAM policies** (least-privilege permissions per role)
5. **Grant state backend access** (all roles can read/write Terraform state)

**Design Goal**: Enable secure, automated Terraform deployments from GitHub Actions with scoped permissions per infrastructure layer.

---

## Resources Created

### GitHub OIDC Provider

Enables GitHub Actions to assume IAM roles using OpenID Connect (OIDC) federation, eliminating the need for long-lived AWS credentials.

```hcl
# Get GitHub OIDC thumbprint
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint,
  ]

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "rbac"
    Purpose      = "GitHub Actions OIDC authentication"
  }
}
```

**Trusted Repository**: `noise2signal/iac-aws` (configured in role trust policies)

### IAM Roles

#### Tfstate Terraform Role

**Purpose**: Manage state backend infrastructure (S3 bucket, DynamoDB table)

```hcl
resource "aws_iam_role" "tfstate_terraform" {
  name        = "tfstate-terraform-role"
  description = "Terraform execution role for tfstate-backend layer"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "rbac"
    Purpose      = "Terraform execution for tfstate-backend layer"
  }
}

# Trust policy for GitHub OIDC
data "aws_iam_policy_document" "github_oidc_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:noise2signal/iac-aws:*"]
    }
  }
}

# Permissions policy
data "aws_iam_policy_document" "tfstate_terraform" {
  statement {
    sid    = "ManageStateBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::n2s-terraform-state-whollyowned",
      "arn:aws:s3:::n2s-terraform-state-whollyowned/*",
    ]
  }

  statement {
    sid    = "ManageLockTable"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:UpdateTable",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
    ]
    resources = [
      "arn:aws:dynamodb:us-east-1:*:table/n2s-terraform-state-whollyowned-lock",
    ]
  }
}

resource "aws_iam_role_policy" "tfstate_terraform" {
  name   = "tfstate-terraform-policy"
  role   = aws_iam_role.tfstate_terraform.id
  policy = data.aws_iam_policy_document.tfstate_terraform.json
}
```

**Scoped Permissions**: Can only manage `n2s-terraform-state-whollyowned` bucket and `n2s-terraform-state-whollyowned-lock` table.

#### Domains Terraform Role

**Purpose**: Manage Route53 hosted zones and ACM certificates

```hcl
resource "aws_iam_role" "domains_terraform" {
  name        = "domains-terraform-role"
  description = "Terraform execution role for domains layer"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "rbac"
    Purpose      = "Terraform execution for domains layer"
  }
}

data "aws_iam_policy_document" "domains_terraform" {
  statement {
    sid    = "ManageRoute53Zones"
    effect = "Allow"
    actions = [
      "route53:CreateHostedZone",
      "route53:DeleteHostedZone",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:UpdateHostedZoneComment",
      "route53:GetChange",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:GetHostedZoneCount",
      "route53:ListTagsForResource",
      "route53:ChangeTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageACMCertificates"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:GetCertificate",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "domains_terraform" {
  name   = "domains-terraform-policy"
  role   = aws_iam_role.domains_terraform.id
  policy = data.aws_iam_policy_document.domains_terraform.json
}
```

**Scoped Permissions**: Route53 hosted zones (NOT domain registrations), ACM certificates.

**Note**: Cannot manage Route53 domain registrations - those are managed in the management account only.

#### Sites Terraform Role

**Purpose**: Manage S3 buckets, CloudFront distributions, and DNS records

```hcl
resource "aws_iam_role" "sites_terraform" {
  name        = "sites-terraform-role"
  description = "Terraform execution role for sites layer"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "rbac"
    Purpose      = "Terraform execution for sites layer"
  }
}

data "aws_iam_policy_document" "sites_terraform" {
  statement {
    sid    = "ManageS3Buckets"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketWebsite",
      "s3:PutBucketWebsite",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::*.noise2signal.com",
      "arn:aws:s3:::*.noise2signal.com/*",
      "arn:aws:s3:::camdenwander.com",
      "arn:aws:s3:::camdenwander.com/*",
      "arn:aws:s3:::www.camdenwander.com",
      "arn:aws:s3:::www.camdenwander.com/*",
    ]
  }

  statement {
    sid    = "ManageCloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:ListDistributions",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetOriginAccessControlConfig",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:ListOriginAccessControls",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
      "cloudfront:CreateInvalidation",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageDNSRecords"
    effect = "Allow"
    actions = [
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:GetChange",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadACMCertificates"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "acm:GetCertificate",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sites_terraform" {
  name   = "sites-terraform-policy"
  role   = aws_iam_role.sites_terraform.id
  policy = data.aws_iam_policy_document.sites_terraform.json
}
```

**Scoped Permissions**: S3 buckets (domain-based), CloudFront distributions, Route53 records (read hosted zones from domains layer), ACM certificates (read-only).

### State Backend Access Policy (Shared)

All Terraform roles need access to the state backend (after tfstate-backend layer is deployed):

```hcl
data "aws_iam_policy_document" "state_backend_access" {
  statement {
    sid    = "ReadWriteStateBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::n2s-terraform-state-whollyowned",
      "arn:aws:s3:::n2s-terraform-state-whollyowned/*",
    ]
  }

  statement {
    sid    = "StateLocking"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      "arn:aws:dynamodb:us-east-1:*:table/n2s-terraform-state-whollyowned-lock",
    ]
  }
}

resource "aws_iam_role_policy" "tfstate_backend_access_tfstate" {
  name   = "state-backend-access"
  role   = aws_iam_role.tfstate_terraform.id
  policy = data.aws_iam_policy_document.state_backend_access.json
}

resource "aws_iam_role_policy" "tfstate_backend_access_domains" {
  name   = "state-backend-access"
  role   = aws_iam_role.domains_terraform.id
  policy = data.aws_iam_policy_document.state_backend_access.json
}

resource "aws_iam_role_policy" "tfstate_backend_access_sites" {
  name   = "state-backend-access"
  role   = aws_iam_role.sites_terraform.id
  policy = data.aws_iam_policy_document.state_backend_access.json
}
```

**Note**: This policy is attached when roles are created (before state backend exists). The policy will work once the tfstate-backend layer is deployed.

---

## Variables

### Required Variables

None - all values are hardcoded for the whollyowned account.

### Optional Variables

```hcl
variable "github_org" {
  type        = string
  description = "GitHub organization or username"
  default     = "noise2signal"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
  default     = "iac-aws"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}
```

---

## Outputs

```hcl
output "github_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "GitHub OIDC provider ARN"
}

output "tfstate_terraform_role_arn" {
  value       = aws_iam_role.tfstate_terraform.arn
  description = "Tfstate Terraform role ARN"
}

output "domains_terraform_role_arn" {
  value       = aws_iam_role.domains_terraform.arn
  description = "Domains Terraform role ARN"
}

output "sites_terraform_role_arn" {
  value       = aws_iam_role.sites_terraform.arn
  description = "Sites Terraform role ARN"
}

output "role_arns_for_github_actions" {
  value = {
    tfstate = aws_iam_role.tfstate_terraform.arn
    domains = aws_iam_role.domains_terraform.arn
    sites   = aws_iam_role.sites_terraform.arn
  }
  description = "Map of role ARNs for GitHub Actions workflows"
}
```

---

## Authentication & Permissions

### Initial Deployment

**Authentication**: AWS SSO admin (via management account)

**AWS CLI Profile Setup**:

```bash
# Configure SSO profile for whollyowned account
aws configure sso
# SSO start URL: https://d-xxxxxxxxxx.awsapps.com/start
# Account: Select whollyowned account
# Role: AdministratorAccess
# Profile name: whollyowned-admin

# Log in
aws sso login --profile whollyowned-admin

# Verify access
aws sts get-caller-identity --profile whollyowned-admin
```

**Required Permissions** (via SSO AdministratorAccess):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider"
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
  region = "us-east-1"
  # Uses AWS_PROFILE environment variable or --profile flag
}
```

**No Cross-Account Access**: This layer does NOT require access to the management account.

---

## State Management

### Initial State (Local)

This layer uses **local state initially** (first layer deployed, no state backend exists yet):

```hcl
# backend.tf (initially commented out)
# terraform {
#   backend "s3" {
#     bucket         = "n2s-terraform-state-whollyowned"
#     key            = "whollyowned/rbac.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-whollyowned-lock"
#     encrypt        = true
#   }
# }
```

### Migration to Remote State (After Layer 1)

After deploying `tfstate-backend` layer, migrate to remote state:

```bash
cd whollyowned/rbac
# Uncomment backend.tf
terraform init -migrate-state
# Answer "yes" to migrate local state to S3
```

---

## Deployment

### Prerequisites

1. Management account deployed (organization, SSO)
2. Whollyowned account created (by organization layer)
3. SSO access configured (boss user can access whollyowned account)
4. AWS CLI configured with whollyowned SSO profile

### Step 1: Access Whollyowned Account

```bash
# Configure SSO profile (if not already done)
aws configure sso --profile whollyowned-admin

# Log in
aws sso login --profile whollyowned-admin

# Verify access
aws sts get-caller-identity --profile whollyowned-admin
# Expected: Account ID matches whollyowned account
```

### Step 2: Initialize Terraform

```bash
cd whollyowned/rbac
terraform init
```

**Expected Output**: Local backend initialized (no S3 backend yet)

### Step 3: Review Plan

```bash
terraform plan
```

**Expected Resources**:
- 1 GitHub OIDC provider
- 3 IAM roles (tfstate, domains, sites)
- 6 IAM role policies (3 layer-specific + 3 state backend access)

**Total**: 10 resources

### Step 4: Apply

```bash
terraform apply
```

**Timeline**: ~1-2 minutes

### Step 5: Verify Resources

```bash
# Verify OIDC provider
aws iam list-open-id-connect-providers --profile whollyowned-admin
# Expected: GitHub OIDC provider in list

# Verify roles
aws iam list-roles --profile whollyowned-admin | grep terraform-role
# Expected: tfstate-terraform-role, domains-terraform-role, sites-terraform-role

# Get role ARNs for GitHub Actions
terraform output role_arns_for_github_actions
```

### Step 6: Record Role ARNs

**For GitHub Actions workflows**:

```bash
terraform output -json role_arns_for_github_actions | jq .
# Copy ARNs for use in .github/workflows/*.yml
```

**Example Output**:
```json
{
  "tfstate": "arn:aws:iam::123456789012:role/tfstate-terraform-role",
  "domains": "arn:aws:iam::123456789012:role/domains-terraform-role",
  "sites": "arn:aws:iam::123456789012:role/sites-terraform-role"
}
```

### Step 7: Proceed to Next Layer

**Next**: Deploy `whollyowned/tfstate-backend` layer (optional, state management)

---

## Testing IAM Roles

### Test GitHub OIDC Assumption (Local Simulation)

You cannot directly test OIDC assumption locally (requires GitHub Actions), but you can verify trust policies:

```bash
# Get trust policy for domains role
aws iam get-role --role-name domains-terraform-role --profile whollyowned-admin \
  --query 'Role.AssumeRolePolicyDocument'

# Expected: Trust policy allows GitHub OIDC provider with repo:noise2signal/iac-aws:*
```

### Test Role Permissions (Manual Assume)

Use SSO admin to manually assume a role and test permissions:

```bash
# Assume domains role
aws sts assume-role \
  --role-arn arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/domains-terraform-role \
  --role-session-name test-session \
  --profile whollyowned-admin

# Export credentials (copy from output)
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>

# Test allowed operations
aws route53 list-hosted-zones
# Expected: Success (or empty list if no zones yet)

aws acm list-certificates --region us-east-1
# Expected: Success (or empty list if no certificates yet)

# Test denied operations
aws s3 ls
# Expected: Access Denied (domains role cannot access S3 except for state backend)

aws ec2 describe-instances --region us-east-1
# Expected: Access Denied (SCP denies EC2)
```

### Test GitHub Actions Integration (After GitHub Workflow Setup)

Trigger a GitHub Actions workflow that uses OIDC:

```bash
# Push a change to trigger workflow
git commit --allow-empty -m "Test OIDC role assumption"
git push origin main

# Check GitHub Actions logs for role assumption success
# Expected: "Assuming role arn:aws:iam::123456789012:role/domains-terraform-role"
```

---

## Post-Deployment Tasks

### 1. Update GitHub Secrets (Optional)

If using repository variables for role ARNs:

```bash
# In GitHub repository settings, add variables:
# - WHOLLYOWNED_ACCOUNT_ID: <account-id>
# - TFSTATE_ROLE_ARN: <tfstate-role-arn>
# - DOMAINS_ROLE_ARN: <domains-role-arn>
# - SITES_ROLE_ARN: <sites-role-arn>
```

Or use hardcoded ARNs in workflow files (simpler, less maintenance).

### 2. Test Role Session Duration

Verify short-lived tokens expire after 1 hour:

```bash
# Assume role via OIDC (in GitHub Actions)
# Wait 61 minutes
# Try to use credentials
# Expected: ExpiredToken error
```

### 3. Proceed to Next Layer

**Next**: Deploy `whollyowned/tfstate-backend` layer

---

## Troubleshooting

### Error: Cannot Access Whollyowned Account

**Symptoms**: `aws sts get-caller-identity` fails or shows wrong account

**Cause**: SSO not configured, wrong profile, permission set not assigned

**Resolution**:

```bash
# Verify SSO configuration
aws configure list-profiles
# Expected: whollyowned-admin in list

# Re-login to SSO
aws sso logout --profile whollyowned-admin
aws sso login --profile whollyowned-admin

# Verify SSO permission set assignment in management account
# Management account > IAM Identity Center > AWS accounts > whollyowned > Assignments
```

### Error: OIDC Provider Already Exists

**Symptoms**: `terraform apply` fails with "EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists"

**Cause**: OIDC provider already created (manual or previous deployment)

**Resolution**:

```bash
# Import existing provider into Terraform state
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com

# Re-run apply
terraform apply
```

### Error: Role Already Exists

**Symptoms**: `terraform apply` fails with "EntityAlreadyExists: Role with name X already exists"

**Cause**: Role already created (manual or previous deployment)

**Resolution**:

```bash
# Import existing role into Terraform state
terraform import aws_iam_role.domains_terraform domains-terraform-role

# Re-run apply
terraform apply
```

### Error: GitHub Actions Cannot Assume Role

**Symptoms**: GitHub Actions workflow fails with "User: arn:aws:sts::123456789012:assumed-role/... is not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Cause**: Trust policy misconfigured, repository name mismatch, OIDC provider missing

**Resolution**:

1. Verify OIDC provider exists: `aws iam list-open-id-connect-providers --profile whollyowned-admin`
2. Verify trust policy: `aws iam get-role --role-name domains-terraform-role --profile whollyowned-admin`
3. Check repository name in trust policy: Should be `repo:noise2signal/iac-aws:*`
4. Verify GitHub Actions workflow uses correct role ARN
5. Check GitHub Actions permissions: Must include `id-token: write`

### Error: Insufficient Permissions for Role

**Symptoms**: Terraform operations fail with "Access Denied" despite using correct role

**Cause**: IAM policy too restrictive, missing permissions, SCP denial

**Resolution**:

1. Check role permissions: `aws iam list-role-policies --role-name domains-terraform-role --profile whollyowned-admin`
2. Get policy document: `aws iam get-role-policy --role-name domains-terraform-role --policy-name domains-terraform-policy --profile whollyowned-admin`
3. Verify required actions are allowed
4. Check SCP restrictions (Workloads OU SCP may deny service)
5. Update IAM policy in RBAC layer, re-apply

---

## Security Considerations

### Least Privilege

- **One role per layer**: Each role can only manage its layer's resources
- **Scoped resource ARNs**: Roles restricted to specific S3 buckets, DynamoDB tables (where possible)
- **No cross-layer access**: Domains role cannot modify sites infrastructure, etc.

### Short-Lived Credentials

- **Session duration**: 1 hour (default OIDC token lifetime)
- **No long-lived credentials**: No IAM access keys, no secret keys in GitHub
- **Automatic expiration**: Tokens expire without manual revocation

### Trust Policy Restrictions

- **Repository-scoped**: Only `repo:noise2signal/iac-aws:*` can assume roles
- **OIDC audience validation**: `sts.amazonaws.com` audience required
- **No other principals**: Roles cannot be assumed by IAM users or other roles

### Audit Trail

- **CloudTrail logs**: All role assumptions logged (who, when, from where)
- **GitHub Actions logs**: Workflow runs show role ARNs and operations
- **Monitor for anomalies**: Unexpected role assumptions, unusual API calls

### Defense in Depth

- **SCPs**: Workloads OU SCP restricts services (even if IAM policy allows)
- **IAM policies**: Role-level permissions (least privilege)
- **Resource policies**: S3 bucket policies, CloudFront OAC (additional layer)

---

## Cost Considerations

**IAM Roles**: Free (no AWS charges for IAM roles)

**OIDC Provider**: Free (no AWS charges for OIDC providers)

**Indirect Benefits**:
- No IAM access key rotation overhead (no long-lived credentials)
- Reduced security risk (short-lived tokens)

**Included in**: Whollyowned account cost allocation (CostCenter: whollyowned)

---

## References

### Related Layers

- [../CLAUDE.md](../CLAUDE.md) - Whollyowned account overview
- [../tfstate-backend/CLAUDE.md](../tfstate-backend/CLAUDE.md) - Next layer (state backend)
- [../domains/CLAUDE.md](../domains/CLAUDE.md) - Domains layer (uses domains-terraform-role)
- [../sites/CLAUDE.md](../sites/CLAUDE.md) - Sites layer (uses sites-terraform-role)

### Parent Documentation

- [../../CLAUDE.md](../../CLAUDE.md) - Overall architecture
- [../../management/CLAUDE.md](../../management/CLAUDE.md) - Management account overview

### AWS Documentation

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [IAM Roles for OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

---

**Layer**: 0 (RBAC)
**Account**: noise2signal-llc-whollyowned
**Last Updated**: 2026-01-26
