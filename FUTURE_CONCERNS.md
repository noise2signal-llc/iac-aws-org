# FUTURE CONCERNS

Architecture design changes and features deferred to future iterations.

---

## Deferred Account Structure

### Additional Accounts Under Proprietary Workloads OU

**Proprietary Noise (Development Account)** - deferred
```
Purpose: Development, staging, and experimental workloads
Resources:
- Development versions of static sites
- Staging environments for testing
- Experimental infrastructure

Why deferred: Single production account sufficient for initial launch
When to implement: When development/staging workflow becomes necessary
```

### Client Account Structure

**Future Client OUs** - deferred
```
Root
└── Client OUs (commissioned workloads)
    ├── Rosen Association OU
    │   ├── Rosen Association Signals (production)
    │   └── Rosen Association Noise (development)
    │
    └── P.P. Layouts OU
        ├── P.P. Layouts Signals (production)
        └── P.P. Layouts Noise (development)
```

**Design Pattern:**
- Each client gets dedicated OU
- Each client gets production + development accounts
- Billing isolation: Separate cost centers per client
- Security boundary: Clients cannot access each other's resources
- Ownership transfer: Easy to transfer OU/accounts to client

**Why deferred:**
- No commissioned clients yet
- Pattern documented for future scaling
- Can implement when first client project confirmed

---

## Service Control Policies (SCPs)

### Management OU SCPs - deferred

**Minimal restrictions for governance operations:**

```hcl
# Allow governance services
statement {
  effect = "Allow"
  actions = [
    "organizations:*",
    "iam:*",
    "sso:*",
    "sso-directory:*",
    "identitystore:*",
  ]
  resources = ["*"]
}

# Allow state backend services
statement {
  effect = "Allow"
  actions = [
    "s3:*",
    "dynamodb:*",
  ]
  resources = ["*"]
}

# Allow domain registration
statement {
  effect = "Allow"
  actions = [
    "route53domains:*",
  ]
  resources = ["*"]
}

# Deny destructive organization actions
statement {
  effect = "Deny"
  actions = [
    "organizations:DeleteOrganization",
    "organizations:LeaveOrganization",
  ]
  resources = ["*"]
}
```

### Proprietary Workloads OU SCPs - deferred

**Restrictive service allow-list:**

```hcl
# Allow only specific services for static sites
statement {
  effect = "Allow"
  actions = [
    "iam:*",
    "sts:*",
    "s3:*",
    "cloudfront:*",
    "route53:*",
    "acm:*",
    "cloudwatch:*",
    "logs:*",
  ]
  resources = ["*"]
}

# Enforce us-east-1 for global services
statement {
  effect = "Deny"
  not_actions = [
    "cloudfront:*",
    "acm:*",  # ACM certificates for CloudFront must be in us-east-1
    "route53:*",
    "iam:*",
    "sts:*",
  ]
  resources = ["*"]
  condition {
    test     = "StringNotEquals"
    variable = "aws:RequestedRegion"
    values   = ["us-east-1"]
  }
}

# Deny root user actions
statement {
  effect = "Deny"
  actions = ["*"]
  resources = ["*"]
  condition {
    test     = "StringLike"
    variable = "aws:PrincipalArn"
    values   = ["arn:aws:iam::*:root"]
  }
}
```

**Why deferred:**
- Need to validate service requirements first
- Risk of locking out legitimate operations
- Test in Proprietary Signals account before enforcing

**When to implement:**
- After Proprietary Signals account is operational
- After validating all required services for static sites
- After testing SCP doesn't block legitimate operations

---

## Terraform Remote State Backend

### Current Approach

Local state files stored on operator's machine:
- Simple for single operator
- No additional AWS resources needed
- State backups managed manually

### Future: S3 + DynamoDB State Backend

**Per-Account State Buckets:**

```
Management Account:
s3://n2s-terraform-state-management/
├── organization.tfstate
├── sso.tfstate
└── scp.tfstate (future)

Proprietary Signals Account:
s3://n2s-terraform-state-proprietary-signals/
├── rbac.tfstate
├── zones.tfstate
└── sites.tfstate
```

**S3 Bucket Configuration:**
```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "n2s-terraform-state-management"

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
    Purpose      = "terraform-state-backend"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**DynamoDB Locking Table:**
```hcl
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "terraform-state-lock-management"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
    Purpose      = "terraform-state-locking"
  }
}
```

**Backend Configuration (per layer):**
```hcl
# backend.tf (commented out initially)
terraform {
  backend "s3" {
    bucket         = "n2s-terraform-state-management"
    key            = "organization.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-management"
    profile        = "management-sso"
  }
}
```

**Migration Process:**
1. Deploy state backend resources (S3 + DynamoDB)
2. Uncomment backend.tf in each layer
3. Run `terraform init -migrate-state`
4. Verify migration: `aws s3 ls s3://<bucket>/`
5. Delete local state files after verification

**Benefits:**
- State locking (prevents concurrent modifications)
- State encryption at rest
- State versioning (90-day retention)
- Team collaboration (if additional operators added)

**Why deferred:**
- Single operator doesn't need locking
- Local state simpler for initial deployment
- Additional AWS costs (~$0.30/month)

**When to implement:**
- When adding second operator
- When automation/CI/CD is introduced
- When state backup complexity becomes burden

---

## GitHub OIDC Integration

### Current Approach

Manual Terraform apply by human operator via AWS CLI.

### Future: GitHub Actions CI/CD

**Per-Account OIDC Provider:**

```hcl
# In each account's rbac/ layer
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"  # or "proprietary-signals"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}
```

**Terraform Execution Roles:**

```hcl
# Management account roles
resource "aws_iam_role" "organization_terraform" {
  name               = "GitHubActions-OrganizationTerraform"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    Purpose      = "terraform-automation"
    Repository   = "noise2signal/iac-aws-org"
  }
}

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
      values   = ["repo:noise2signal/iac-aws-org:*"]
    }
  }
}

# Attach policies for Organizations, SSO, SCP management
resource "aws_iam_role_policy_attachment" "organization_terraform" {
  role       = aws_iam_role.organization_terraform.name
  policy_arn = aws_iam_policy.organization_terraform.arn
}
```

**GitHub Actions Workflow:**

```yaml
name: Terraform Apply

on:
  push:
    branches: [main]
    paths:
      - 'organization/**'

permissions:
  id-token: write  # Required for OIDC
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.MANAGEMENT_ACCOUNT_ID }}:role/GitHubActions-OrganizationTerraform
          aws-region: us-east-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init
        working-directory: ./organization

      - name: Terraform Plan
        run: terraform plan
        working-directory: ./organization

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve
        working-directory: ./organization
```

**Benefits:**
- No long-lived AWS credentials in GitHub
- Short-lived session tokens (1 hour)
- Automated deployment on git push
- Per-account isolation

**Why deferred:**
- Manual deployment sufficient for low-frequency changes
- Additional complexity not justified yet
- Risk of automation errors

**When to implement:**
- When deployment frequency increases
- When adding team members who need deploy access
- When manual process becomes burden

---

## Additional Permission Sets

### Current SSO Configuration

Minimal configuration:
- AWS-managed AdministratorAccess permission set
- Single LLC member user

### Future Permission Sets

**PowerUserAccess** - deferred
```hcl
resource "aws_ssoadmin_permission_set" "power_user" {
  name             = "PowerUserAccess"
  description      = "Power user access without IAM/Organizations changes"
  instance_arn     = aws_ssoadmin_instance.main.arn
  session_duration = "PT8H"

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    Purpose      = "developer-access"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "power_user" {
  instance_arn       = aws_ssoadmin_instance.main.arn
  permission_set_arn = aws_ssoadmin_permission_set.power_user.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
```

**ReadOnlyAccess** - deferred
```hcl
resource "aws_ssoadmin_permission_set" "read_only" {
  name             = "ReadOnlyAccess"
  description      = "Read-only access for auditing"
  instance_arn     = aws_ssoadmin_instance.main.arn
  session_duration = "PT4H"

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    Purpose      = "auditor-access"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  instance_arn       = aws_ssoadmin_instance.main.arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

**TerraformDeployAccess** - deferred
```hcl
# Custom permission set for Terraform automation
# Scoped to only resources Terraform needs to manage
resource "aws_ssoadmin_permission_set" "terraform_deploy" {
  name             = "TerraformDeployAccess"
  description      = "Scoped access for Terraform deployment"
  instance_arn     = aws_ssoadmin_instance.main.arn
  session_duration = "PT1H"

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    Purpose      = "terraform-automation"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "terraform_deploy" {
  instance_arn       = aws_ssoadmin_instance.main.arn
  permission_set_arn = aws_ssoadmin_permission_set.terraform_deploy.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "organizations:Describe*",
          "organizations:List*",
          "organizations:CreateAccount",
          "organizations:MoveAccount",
          "organizations:TagResource",
          "organizations:UntagResource",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sso:*",
          "identitystore:*",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::n2s-terraform-state-*",
          "arn:aws:s3:::n2s-terraform-state-*/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = "arn:aws:dynamodb:*:*:table/terraform-state-lock-*"
      },
    ]
  })
}
```

**Why deferred:**
- Single operator only needs admin access
- Additional permission sets add complexity

**When to implement:**
- When adding additional LLC members or contractors
- When implementing principle of least privilege
- When automation needs scoped permissions

---

## Multi-Repository Strategy

### Current Approach

Single repository (`iac-aws-org`) manages management account only.

### Future Repository Structure

**Management Account Infrastructure:**
- Repository: `iac-aws-org` (current)
- Scope: Organizations, OUs, accounts, SSO, SCPs
- Owner: Noise2Signal LLC

**Proprietary Workloads Infrastructure:**
- Repository: `iac-aws-proprietary`
- Scope: Static sites, Route53 zones, CloudFront, S3
- Owner: Noise2Signal LLC
- Separate repository for clear separation of concerns

**Client Workloads Infrastructure:**
- Repository: `client-{name}-infrastructure`
- Scope: Client-specific workloads
- Owner: Client (transfer ownership on project completion)
- Repository can be transferred with AWS account for complete handoff

**Benefits:**
- Clear ownership boundaries
- Easy client handoff (transfer repo + account together)
- Independent version control and deployment cycles

---

## Cost Optimization

### Deferred Optimizations

**CloudFront Reserved Capacity** - deferred until traffic is predictable
**S3 Intelligent Tiering** - deferred until storage costs are significant
**Route53 Traffic Management** - deferred until multi-region deployment

### Billing Alerts

**Per-Account Budget Alerts:**
```hcl
resource "aws_budgets_budget" "account_monthly" {
  name              = "monthly-budget-${var.account_name}"
  budget_type       = "COST"
  limit_amount      = "10"
  limit_unit        = "USD"
  time_period_start = "2026-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_threshold = 80
    threshold            = 80
    threshold_type       = "PERCENTAGE"
    notification_type    = "ACTUAL"
    subscriber_email_addresses = [
      "billing@noise2signal.com"
    ]
  }

  notification {
    comparison_threshold = 100
    threshold            = 100
    threshold_type       = "PERCENTAGE"
    notification_type    = "ACTUAL"
    subscriber_email_addresses = [
      "billing@noise2signal.com"
    ]
  }
}
```

**Why deferred:**
- Current costs are minimal and predictable
- Manual cost monitoring via AWS Console sufficient

**When to implement:**
- When monthly costs exceed $50
- When clients are added (separate billing tracking needed)
- When cost overruns become a concern

---

## Maintenance Operations

### Adding New Member Accounts

Example Terraform for creating new accounts:

```hcl
# In organization/main.tf

# Client account example
resource "aws_organizations_account" "client_acme" {
  name              = "Client ACME Signals"
  email             = "aws+client-acme@noise2signal.com"
  parent_id         = aws_organizations_organizational_unit.client_acme.id
  close_on_deletion = false

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "client-acme"
    CostCenter   = "client-acme"
    Environment  = "production"
    ManagedBy    = "terraform"
    Client       = "ACME Corporation"
  }
}

output "client_acme_account_id" {
  value       = aws_organizations_account.client_acme.id
  description = "Account ID for Client ACME production workloads"
}
```

### Moving Accounts Between OUs

Change `parent_id` in Terraform:

```hcl
resource "aws_organizations_account" "proprietary_signals" {
  name      = "Proprietary Signals"
  email     = "aws+proprietary-signals@noise2signal.com"
  parent_id = aws_organizations_organizational_unit.proprietary_development.id  # Changed
  # ...
}
```

**Impact:** SCPs from new OU apply immediately

---

## Summary

**Current Scope:**
- Management account with Organizations, SSO
- Local state files
- Manual deployment
- Single operator

**Deferred to Future:**
- Additional accounts (Proprietary Noise, Client accounts)
- Service Control Policies
- Remote state backends
- GitHub OIDC automation
- Additional SSO permission sets
- Billing alerts
- Multi-repository strategy

**Decision Criteria for Implementation:**
- Add complexity only when it solves real problem
- Start simple, scale as needed
- Document future patterns for consistency

---

**Last Updated:** 2026-01-27
**Maintained By:** Camden Lindahl, Noise2Signal LLC Member
