# Layer 1: Role-Based Access Control (RBAC)

## Layer Purpose

This layer defines **IAM roles** for Terraform execution across all infrastructure layers. Each layer gets a dedicated IAM role with scoped permissions following the principle of least privilege. This layer also creates the GitHub OIDC provider for federated authentication from GitHub Actions.

**Deployment Order**: Layer 1 (deployed after SCP, before all other layers)

## Scope & Responsibilities

### In Scope
✅ **Terraform Execution Roles**
- One IAM role per infrastructure layer (scp, tfstate-backend, domains, sites)
- Scoped permissions for each role (only what that layer needs)
- Trust policies for human and CI/CD assumption

✅ **GitHub OIDC Provider**
- Federated authentication for GitHub Actions
- Trust relationship for Noise2Signal repositories
- No long-lived AWS credentials required

✅ **Developer Access Roles** (Optional)
- Separate developer roles with broader permissions for exploration
- MFA enforcement for human access
- Session duration policies

### Out of Scope
❌ Service Control Policies (managed in `scp` layer)
❌ Application-specific IAM roles (managed in respective layers if needed)
❌ State backend infrastructure (managed in `tfstate-backend` layer)

## Architecture Context

### Layer Dependencies

```
Layer 0: scp (bootstrap)
    ↓
Layer 1: rbac (IAM roles) ← YOU ARE HERE
    ↓
Layer 2: tfstate-backend (S3 + DynamoDB)
    ↓
Layer 3: domains (Route53 + ACM)
    ↓
Layer 4: sites (S3 + CloudFront + DNS records)
```

### State Management

**State Storage**: Local state file (`.tfstate` in this directory, gitignored)

**Why Local State**:
- RBAC is deployed before tfstate-backend layer exists
- Can be migrated to remote state after `tfstate-backend` layer is deployed

**Deployment Credentials**: AWS administrator credentials (manual/temporary) or `scp-terraform-role` if created

**Future State Migration**: After `tfstate-backend` layer exists, uncomment `backend.tf` and run `terraform init -migrate-state`

## IAM Roles Architecture

### Role Naming Convention

```
{layer}-terraform-role
```

Examples:
- `scp-terraform-role` - For future SCP updates
- `tfstate-backend-terraform-role` - For S3/DynamoDB management
- `domains-terraform-role` - For Route53/ACM management
- `sites-terraform-role` - For S3/CloudFront/DNS management

### Role Trust Policies

Each role allows assumption by:
1. **GitHub OIDC** (for CI/CD automation)
2. **Developer IAM users** (for manual operations, optional)
3. **AWS SSO principals** (if SSO configured)

### Permission Scoping Strategy

Each role has permissions for **only its layer's resources**:

| Role | Allowed Services | Scope |
|------|-----------------|-------|
| `scp-terraform-role` | Organizations | SCP management |
| `tfstate-backend-terraform-role` | S3, DynamoDB | State backend only |
| `domains-terraform-role` | Route53, ACM | DNS and certificates |
| `sites-terraform-role` | S3, CloudFront, Route53 | Website infrastructure |

**Cross-layer access**: Layers use AWS data sources (not IAM cross-role access)

## Resources Managed

### 1. GitHub OIDC Provider

Enables GitHub Actions to assume IAM roles without long-lived credentials.

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",  # GitHub's current thumbprint
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",  # GitHub's backup thumbprint
  ]

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "rbac-layer"
    Purpose     = "github-actions-oidc"
  }
}
```

### 2. SCP Terraform Role

For future SCP updates (post-bootstrap).

```hcl
resource "aws_iam_role" "scp_terraform" {
  name               = "scp-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "rbac-layer"
    Layer       = "0-scp"
  }
}

resource "aws_iam_role_policy" "scp_terraform" {
  name = "scp-terraform-policy"
  role = aws_iam_role.scp_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageServiceControlPolicies"
        Effect = "Allow"
        Action = [
          "organizations:DescribeOrganization",
          "organizations:DescribePolicy",
          "organizations:ListPolicies",
          "organizations:CreatePolicy",
          "organizations:UpdatePolicy",
          "organizations:DeletePolicy",
          "organizations:AttachPolicy",
          "organizations:DetachPolicy",
          "organizations:ListTargetsForPolicy",
        ]
        Resource = "*"
      }
    ]
  })
}
```

### 3. Tfstate Backend Terraform Role

For S3 bucket and DynamoDB table management.

```hcl
resource "aws_iam_role" "tfstate_backend_terraform" {
  name               = "tfstate-backend-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "rbac-layer"
    Layer       = "2-tfstate-backend"
  }
}

resource "aws_iam_role_policy" "tfstate_backend_terraform" {
  name = "tfstate-backend-terraform-policy"
  role = aws_iam_role.tfstate_backend_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageStateBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketEncryption",
          "s3:PutBucketEncryption",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketLifecycleConfiguration",
          "s3:PutBucketLifecycleConfiguration",
        ]
        Resource = "arn:aws:s3:::noise2signal-terraform-state"
      },
      {
        Sid    = "ManageStateLockTable"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = "arn:aws:dynamodb:us-east-1:*:table/noise2signal-terraform-state-lock"
      }
    ]
  })
}
```

### 4. Domains Terraform Role

For Route53 and ACM management.

```hcl
resource "aws_iam_role" "domains_terraform" {
  name               = "domains-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "rbac-layer"
    Layer       = "3-domains"
  }
}

resource "aws_iam_role_policy" "domains_terraform" {
  name = "domains-terraform-policy"
  role = aws_iam_role.domains_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageRoute53Zones"
        Effect = "Allow"
        Action = [
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
        Resource = "*"
      },
      {
        Sid    = "ManageACMCertificates"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DescribeCertificate",
          "acm:DeleteCertificate",
          "acm:ListCertificates",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:ListTagsForCertificate",
        ]
        Resource = "*"
      }
    ]
  })
}
```

### 5. Sites Terraform Role

For S3, CloudFront, and DNS record management.

```hcl
resource "aws_iam_role" "sites_terraform" {
  name               = "sites-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "rbac-layer"
    Layer       = "4-sites"
  }
}

resource "aws_iam_role_policy" "sites_terraform" {
  name = "sites-terraform-policy"
  role = aws_iam_role.sites_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageWebsiteBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketEncryption",
          "s3:PutBucketEncryption",
          "s3:GetBucketWebsite",
          "s3:PutBucketWebsite",
          "s3:DeleteBucketWebsite",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
        ]
        Resource = [
          "arn:aws:s3:::*.camdenwander.com",
          "arn:aws:s3:::camdenwander.com",
          # Add additional domain patterns as sites are added
        ]
      },
      {
        Sid    = "ManageCloudFrontDistributions"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:ListTagsForResource",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:CreateResponseHeadersPolicy",
          "cloudfront:DeleteResponseHeadersPolicy",
          "cloudfront:GetResponseHeadersPolicy",
          "cloudfront:UpdateResponseHeadersPolicy",
          "cloudfront:ListResponseHeadersPolicies",
          "cloudfront:GetCachePolicy",
          "cloudfront:ListCachePolicies",
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageDNSRecords"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadACMCertificates"
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:ListTagsForCertificate",
        ]
        Resource = "*"
      }
    ]
  })
}
```

### 6. Common Trust Policy

All Terraform roles share this trust policy allowing GitHub OIDC and developer access.

```hcl
data "aws_iam_policy_document" "terraform_trust" {
  # GitHub Actions OIDC federation
  statement {
    sid     = "AllowGitHubOIDC"
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
      values   = ["repo:noise2signal/*:*"]  # All Noise2Signal repos
    }
  }

  # Optional: Developer access (uncomment if needed)
  # statement {
  #   sid     = "AllowDeveloperAccess"
  #   effect  = "Allow"
  #   actions = ["sts:AssumeRole"]
  #
  #   principals {
  #     type        = "AWS"
  #     identifiers = ["arn:aws:iam::ACCOUNT_ID:user/developer"]
  #   }
  #
  #   condition {
  #     test     = "Bool"
  #     variable = "aws:MultiFactorAuthPresent"
  #     values   = ["true"]
  #   }
  # }
}
```

### 7. State Backend Access Policy (Attached to All Roles)

All Terraform roles need access to the state backend for storing their layer's state.

```hcl
resource "aws_iam_policy" "terraform_state_access" {
  name        = "terraform-state-backend-access"
  description = "Allows Terraform roles to access state backend"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWriteStateFiles"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::noise2signal-terraform-state/*"
      },
      {
        Sid    = "ListStateBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = "arn:aws:s3:::noise2signal-terraform-state"
      },
      {
        Sid    = "ManageStateLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = "arn:aws:dynamodb:us-east-1:*:table/noise2signal-terraform-state-lock"
      }
    ]
  })
}

# Attach to all Terraform roles
resource "aws_iam_role_policy_attachment" "state_access" {
  for_each = {
    scp              = aws_iam_role.scp_terraform.name
    tfstate_backend  = aws_iam_role.tfstate_backend_terraform.name
    domains          = aws_iam_role.domains_terraform.name
    sites            = aws_iam_role.sites_terraform.name
  }

  role       = each.value
  policy_arn = aws_iam_policy.terraform_state_access.arn
}
```

## Terraform Configuration

### Backend Configuration (Initially Commented)

```hcl
# backend.tf
# Uncomment after tfstate-backend layer is deployed

# terraform {
#   backend "s3" {
#     bucket         = "noise2signal-terraform-state"
#     key            = "noise2signal/rbac.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "noise2signal-terraform-state-lock"
#     encrypt        = true
#   }
# }
```

### Provider Configuration

```hcl
# provider.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # RBAC layer uses admin credentials initially
  # After deployment, future updates can use scp-terraform-role if needed

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "rbac-layer"
      Layer       = "1-rbac"
    }
  }
}
```

### Variables

```hcl
# variables.tf
variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "noise2signal"
}

variable "enable_developer_access" {
  description = "Enable developer IAM user access to Terraform roles"
  type        = bool
  default     = false
}

variable "developer_user_arns" {
  description = "List of IAM user ARNs allowed to assume Terraform roles"
  type        = list(string)
  default     = []
}
```

### Outputs

```hcl
# outputs.tf
output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "terraform_role_arns" {
  description = "Map of layer names to Terraform role ARNs"
  value = {
    scp             = aws_iam_role.scp_terraform.arn
    tfstate_backend = aws_iam_role.tfstate_backend_terraform.arn
    domains         = aws_iam_role.domains_terraform.arn
    sites           = aws_iam_role.sites_terraform.arn
  }
}

output "state_access_policy_arn" {
  description = "ARN of the shared state backend access policy"
  value       = aws_iam_policy.terraform_state_access.arn
}
```

## Deployment Process

### Prerequisites
- SCP layer deployed (Layer 0)
- AWS CLI configured with administrator credentials
- Terraform 1.5+ installed

### Initial Deployment

1. **Navigate to RBAC layer**
   ```bash
   cd /workspace/rbac
   ```

2. **Configure variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with GitHub org and optional developer access
   ```

3. **Initialize Terraform (local state)**
   ```bash
   terraform init
   ```

4. **Plan infrastructure**
   ```bash
   terraform plan -out=tfplan
   # Review: OIDC provider, IAM roles, policies
   ```

5. **Apply RBAC configuration**
   ```bash
   terraform apply tfplan
   ```

6. **Verify role creation**
   ```bash
   aws iam list-roles | grep terraform-role
   ```

7. **Note role ARNs for other layers**
   ```bash
   terraform output terraform_role_arns
   # Copy ARNs for use in provider.tf of other layers
   ```

## Using Terraform Roles in Other Layers

### In Provider Configuration

Each layer's `provider.tf` should assume its dedicated role:

```hcl
# Example: domains/provider.tf
provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::ACCOUNT_ID:role/domains-terraform-role"
    session_name = "terraform-domains-session"
  }

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "domains-layer"
      Layer       = "3-domains"
    }
  }
}
```

### In GitHub Actions Workflows

```yaml
# Example: .github/workflows/domains-deploy.yml
name: Deploy Domains Layer

on:
  push:
    branches: [main]
    paths:
      - 'domains/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/domains-terraform-role
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: ./domains
        run: terraform init

      - name: Terraform Apply
        working-directory: ./domains
        run: terraform apply -auto-approve
```

## Security Considerations

### Principle of Least Privilege
- Each role has permissions ONLY for its layer's resources
- No wildcard resource ARNs where specific ARNs can be used
- State backend access is shared but scoped to read/write operations only

### Credential Security
- GitHub OIDC eliminates long-lived AWS credentials
- No AWS access keys stored in GitHub secrets
- Session tokens are short-lived (1 hour default)

### Role Assumption Constraints
- GitHub OIDC limited to `noise2signal/*` repositories
- Optional MFA requirement for developer access
- Session tags for attribution and audit trails

### Defense in Depth
- SCP layer constrains services even if IAM policies misconfigured
- IAM roles enforce resource-level permissions
- State backend encryption protects sensitive data at rest

## Dependencies

### Upstream Dependencies
- `scp` layer (Layer 0) - Defines allowed services

### Downstream Dependencies
- All other layers assume roles created here
- `tfstate-backend` layer requires state access policy
- GitHub Actions workflows reference role ARNs

## Cost Estimates

**IAM Roles and Policies**: Free (no AWS charges)

**GitHub OIDC Provider**: Free

**Time Cost**: ~10 minutes initial setup

## Testing & Validation

### Post-Deployment Checks
- [ ] GitHub OIDC provider exists
- [ ] All Terraform roles created (scp, tfstate-backend, domains, sites)
- [ ] Trust policies allow GitHub OIDC assumption
- [ ] State backend access policy attached to all roles
- [ ] Roles can be assumed from GitHub Actions (test in workflow)

### Validation Commands

```bash
# List IAM roles
aws iam list-roles | jq '.Roles[] | select(.RoleName | contains("terraform-role"))'

# Verify OIDC provider
aws iam list-open-id-connect-providers

# Test role assumption (from GitHub Actions or with credentials)
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/domains-terraform-role \
  --role-session-name test-session

# Verify policy attachments
aws iam list-attached-role-policies --role-name domains-terraform-role
```

## Maintenance & Updates

### Adding New Layers
When adding new infrastructure layers:
1. Create new IAM role in this layer
2. Define scoped permissions for new layer's resources
3. Attach state backend access policy
4. Output role ARN for use in new layer's provider

### Updating Permissions
When layers require additional permissions:
1. Update role policy in `main.tf`
2. Apply changes with `terraform apply`
3. Verify new permissions work in target layer

### Rotating GitHub OIDC Thumbprints
GitHub occasionally rotates certificates:
1. Get new thumbprint from GitHub documentation
2. Update `thumbprint_list` in OIDC provider
3. Apply changes

## Troubleshooting

### Role Assumption Failures from GitHub Actions
**Symptoms**: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Causes**:
- OIDC provider not created
- Trust policy doesn't include GitHub repo
- GitHub workflow missing `id-token: write` permission

**Resolution**:
```bash
# Verify OIDC provider exists
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn <PROVIDER_ARN>

# Check role trust policy
aws iam get-role --role-name domains-terraform-role \
  | jq '.Role.AssumeRolePolicyDocument'
```

### Access Denied in Other Layers
**Symptoms**: Terraform operations fail with permission errors

**Causes**:
- Role doesn't have required permissions
- Resource ARN not in policy scope
- SCP blocking service

**Resolution**:
1. Identify missing permission from error
2. Update role policy to add permission
3. Verify SCP allows the service
4. Apply RBAC changes and retry

### State Backend Access Issues
**Symptoms**: "Error acquiring state lock" or "Access denied" on state operations

**Causes**:
- State access policy not attached to role
- S3 bucket or DynamoDB table doesn't exist yet

**Resolution**:
```bash
# Verify policy attachment
aws iam list-attached-role-policies --role-name domains-terraform-role

# Manually attach if missing
aws iam attach-role-policy \
  --role-name domains-terraform-role \
  --policy-arn <STATE_ACCESS_POLICY_ARN>
```

## Future Enhancements

- Separate GitHub Actions vs Developer roles (different permission scopes)
- Session duration customization per role
- CloudTrail integration for role usage auditing
- AWS SSO integration for developer access
- Conditional access based on source IP or time of day

## References

- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [IAM Role Trust Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html)
- [Terraform AWS Provider - Assume Role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#assume-role)
