# Terraform Inception - Bootstrap Infrastructure

## Repository Purpose

This repository provisions the foundational infrastructure required for **all other Terraform repositories** in the Noise2Signal LLC AWS account. This is the first repository deployed after manual AWS account creation ("post-click-ops").

**GitHub Repository**: `terraform-inception`

## Scope & Responsibilities

### In Scope
✅ **Terraform State Backend**
- S3 bucket for remote state storage
- DynamoDB table for state locking
- Bucket encryption, versioning, and lifecycle policies
- State file organization structure (prefix-based)

✅ **IAM Roles for Terraform Execution**
- **GitHub Actions Role** - OIDC-federated, fine-grained permissions for CI/CD
- **Developer Role** - Expanded permissions for human exploration/drafting
- Policies scoped to Terraform operations only

✅ **Account-Level Tags & Standards**
- Default tags enforced across account
- Naming convention enforcement (where possible via IAM conditions)

### Out of Scope
❌ Route53 hosted zones (managed in `terraform-dns-domains`)
❌ ACM certificates (managed in `terraform-dns-domains`)
❌ Website infrastructure (managed in `terraform-static-sites`)
❌ Application-specific IAM roles (managed in respective repos)
❌ CloudWatch log groups (managed where logs are generated)

## Architecture Context

### Multi-Repo Strategy
This repo is **Tier 1** in a 3-tier architecture:

1. **Tier 1: terraform-inception** ← YOU ARE HERE
   - Terraform harness (state backend, execution roles)

2. **Tier 2: terraform-dns-domains**
   - Domain ownership (Route53 zones, ACM certificates)

3. **Tier 3: terraform-static-sites**
   - Website infrastructure (S3, CloudFront, Route53 records)

**Plus**: Module repositories for reusable components

### State File Organization

This repo provisions the state backend that ALL repos use:

```
s3://noise2signal-terraform-state/
└── noise2signal/
    ├── inception.tfstate          ← This repo's state (bootstrap problem)
    ├── dns-domains.tfstate         ← Used by terraform-dns-domains
    └── static-sites.tfstate        ← Used by terraform-static-sites

└── client-<name>/                  ← Future: commissioned work
    └── ...
```

**Bootstrap Problem**: This repo's initial state is local, then migrated to S3 after backend is created.

## Resources Managed

### 1. S3 State Backend Bucket

**Requirements:**
- **Bucket name**: `noise2signal-terraform-state` (globally unique, adjust if taken)
- **Versioning**: Enabled (state file recovery)
- **Encryption**: AES256 server-side encryption (AWS managed keys)
- **Lifecycle policy**: Delete non-current versions after 90 days (cost control)
- **Public access**: Blocked (all 4 settings)
- **Bucket policy**: Restrict access to Terraform execution roles only

**Tags:**
```hcl
{
  Owner       = "Noise2Signal LLC"
  Environment = "global"
  Terraform   = "true"
  Purpose     = "terraform-state-backend"
}
```

### 2. DynamoDB State Lock Table

**Requirements:**
- **Table name**: `noise2signal-terraform-state-lock`
- **Primary key**: `LockID` (String)
- **Billing mode**: PAY_PER_REQUEST (cost-effective for low-frequency locks)
- **Encryption**: AWS managed keys
- **Point-in-time recovery**: Optional (consider for production)

**Tags:**
```hcl
{
  Owner       = "Noise2Signal LLC"
  Environment = "global"
  Terraform   = "true"
  Purpose     = "terraform-state-locking"
}
```

### 3. GitHub Actions IAM Role (OIDC)

**Requirements:**
- **Trust policy**: GitHub OIDC provider (repo: `noise2signal/*`)
- **Permissions**: Fine-grained for known deployments
  - S3: PutObject, GetObject on state bucket (with prefix restrictions)
  - DynamoDB: PutItem, GetItem, DeleteItem on lock table
  - Route53: CreateHostedZone, ChangeResourceRecordSets (specific zones)
  - ACM: RequestCertificate, DescribeCertificate (us-east-1 only)
  - CloudFront: CreateDistribution, UpdateDistribution
  - S3: CreateBucket, PutBucketPolicy (website buckets only)
  - IAM: PassRole (for CloudFront OAC, if needed)

**Naming**: `github-actions-terraform-role`

**Session duration**: 1 hour (GitHub Actions workflow runtime)

**Tags:**
```hcl
{
  Owner       = "Noise2Signal LLC"
  Purpose     = "github-ci-terraform-execution"
  Terraform   = "true"
}
```

### 4. Developer Terraform IAM Role

**Requirements:**
- **Trust policy**: AWS SSO principal or specific IAM users
- **Permissions**: Expanded for exploration
  - All GitHub Actions permissions, PLUS:
  - IAM: CreateRole, AttachRolePolicy (for prototyping)
  - CloudWatch: CreateLogGroup, PutMetricAlarm
  - Additional services as needed (scoped to account)

**Naming**: `developer-terraform-role`

**Session duration**: 12 hours (long dev sessions)

**MFA requirement**: Optional but recommended

**Tags:**
```hcl
{
  Owner       = "Noise2Signal LLC"
  Purpose     = "developer-terraform-exploration"
  Terraform   = "true"
}
```

### 5. GitHub OIDC Provider

**Requirements:**
- **Provider URL**: `https://token.actions.githubusercontent.com`
- **Audience**: `sts.amazonaws.com`
- **Thumbprint**: GitHub's current thumbprint (check AWS docs)

This allows GitHub Actions to assume the IAM role without long-lived credentials.

## Terraform Configuration Standards

### Backend Configuration (Bootstrap Problem)

**Initial deployment** (local state):
```hcl
# backend.tf (commented out initially)
# terraform {
#   backend "s3" {
#     bucket         = "noise2signal-terraform-state"
#     key            = "noise2signal/inception.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "noise2signal-terraform-state-lock"
#     encrypt        = true
#   }
# }
```

**After initial apply**:
1. Uncomment backend configuration
2. Run `terraform init -migrate-state`
3. Confirm state migration to S3
4. Delete local `terraform.tfstate` file

### Provider Configuration

```hcl
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

  default_tags {
    tags = {
      Owner     = "Noise2Signal LLC"
      Terraform = "true"
      ManagedBy = "terraform-inception"
    }
  }
}
```

### Variables

**Required variables:**
```hcl
variable "aws_region" {
  description = "AWS region for global resources"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "noise2signal-terraform-state"
}

variable "state_lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "noise2signal-terraform-state-lock"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "noise2signal"
}
```

### Outputs

**Required outputs:**
```hcl
output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_lock_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_lock.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "developer_role_arn" {
  description = "IAM role ARN for developer Terraform access"
  value       = aws_iam_role.developer.arn
}

output "state_bucket_region" {
  description = "AWS region of state bucket"
  value       = aws_s3_bucket.terraform_state.region
}
```

## Deployment Process

### Prerequisites
- AWS account created (manual)
- AWS CLI configured with administrative credentials (temporary, for bootstrap only)
- Terraform 1.5+ installed locally
- GitHub organization/account exists

### Initial Deployment Steps

1. **Clone repository**
   ```bash
   git clone https://github.com/noise2signal/terraform-inception.git
   cd terraform-inception
   ```

2. **Review and customize variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize Terraform (local state)**
   ```bash
   terraform init
   ```

4. **Plan infrastructure**
   ```bash
   terraform plan -out=tfplan
   ```

5. **Apply infrastructure**
   ```bash
   terraform apply tfplan
   ```

6. **Migrate state to S3**
   - Uncomment `backend.tf` configuration
   - Run: `terraform init -migrate-state`
   - Confirm migration
   - Delete local `terraform.tfstate*` files
   - Commit and push backend configuration

7. **Verify remote state**
   ```bash
   aws s3 ls s3://noise2signal-terraform-state/noise2signal/
   # Should show: inception.tfstate
   ```

### Subsequent Updates

After initial bootstrap, all changes use remote state:
```bash
terraform init       # Initializes with S3 backend
terraform plan
terraform apply
```

## Security Considerations

### State File Security
- State files contain sensitive data (resource IDs, some configurations)
- S3 bucket encryption is MANDATORY
- Bucket policy restricts access to Terraform execution roles only
- Versioning enabled for recovery from accidental deletions
- Public access blocked at bucket and account level

### IAM Role Least Privilege
- GitHub Actions role has ONLY permissions for known deployments
- Deny policies for high-risk actions (DeleteBucket, DeleteTable, etc.)
- Scope permissions to specific resource ARNs where possible
- Separate roles for CI/CD vs human development

### Secrets Management
- NO credentials in code or state file names
- GitHub OIDC for federated access (no long-lived keys)
- AWS Secrets Manager or SSM Parameter Store for application secrets (not managed here)

### Audit & Monitoring
- CloudTrail enabled (assumed at account level, not managed here)
- S3 bucket logging (optional, consider cost vs benefit)
- IAM role session tags for attribution

## Dependencies

### Upstream Dependencies
- **None** - This is the foundational repository

### Downstream Dependencies
All other Terraform repositories depend on this repo:
- `terraform-dns-domains` - Uses state backend and IAM roles
- `terraform-static-sites` - Uses state backend and IAM roles
- Module repositories - Reference outputs for standards

## Cost Estimates

Monthly costs (low usage):
- S3 bucket: ~$0.10 (state files are small)
- DynamoDB: ~$0.25 (PAY_PER_REQUEST, minimal locking)
- IAM roles: Free
- **Total: ~$0.35/month**

## Testing & Validation

### Post-Deployment Checks
- [ ] S3 bucket exists and is encrypted
- [ ] DynamoDB table exists and is active
- [ ] GitHub Actions role can be assumed from GitHub workflow
- [ ] Developer role can be assumed (test with AWS CLI)
- [ ] State file successfully migrated to S3
- [ ] State locking works (run concurrent `terraform plan` commands)

### Validation Commands
```bash
# Verify state bucket
aws s3api head-bucket --bucket noise2signal-terraform-state

# Verify encryption
aws s3api get-bucket-encryption --bucket noise2signal-terraform-state

# Verify DynamoDB table
aws dynamodb describe-table --table-name noise2signal-terraform-state-lock

# Test GitHub Actions role (from GitHub workflow)
aws sts get-caller-identity
```

## Maintenance & Updates

### Regular Maintenance
- Review IAM policies quarterly (adjust as permissions needs change)
- Monitor state bucket size (should remain small)
- Clean up old state versions if bucket grows
- Update Terraform provider versions annually

### Breaking Changes
- Bucket or table renaming requires state migration (high risk)
- IAM role renaming requires downstream repo updates
- Prefer updating in-place over recreating resources

## Troubleshooting

### State Locking Issues
If state is locked and won't release:
```bash
# List locks
aws dynamodb scan --table-name noise2signal-terraform-state-lock

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### GitHub Actions Authentication Failures
- Verify OIDC provider is configured
- Check role trust policy includes correct GitHub repo
- Confirm workflow uses `id-token: write` permission

### State Migration Failures
- Ensure backend configuration is correct
- Verify IAM permissions for state bucket access
- Check S3 bucket exists before migration

## Future Enhancements

- Multi-region state replication (disaster recovery)
- State file MFA delete protection (S3 bucket feature)
- Automated IAM policy review (AWS Access Analyzer)
- Terraform Cloud migration (if scaling to larger team)

## References

- [Terraform S3 Backend Documentation](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
