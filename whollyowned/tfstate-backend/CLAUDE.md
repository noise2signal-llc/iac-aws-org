# Whollyowned Account - Tfstate Backend Layer

## Purpose

The **tfstate-backend layer** creates the S3 bucket and DynamoDB table for storing Terraform state files for all layers in the **whollyowned account**. This is an optional layer deployed after RBAC, enabling migration from local to remote state storage.

**This is Layer 1** - deployed after the RBAC layer.

---

## Responsibilities

1. **Create S3 bucket** for Terraform state storage (`n2s-terraform-state-whollyowned`)
2. **Enable versioning** on S3 bucket (recover from accidental deletions)
3. **Enable encryption** on S3 bucket (AES256 server-side encryption)
4. **Configure lifecycle policies** (retain old versions for 90 days)
5. **Create DynamoDB table** for state locking (`n2s-terraform-state-whollyowned-lock`)
6. **Output bucket/table names** for backend configuration

**Design Goal**: Provide durable, secure, and concurrent-safe storage for whollyowned account Terraform state files, separate from the management account state backend.

---

## Resources Created

### S3 Bucket

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "n2s-terraform-state-whollyowned"

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "tfstate-backend"
    Purpose      = "Terraform state storage for whollyowned account"
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

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
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

**Bucket Name**: `n2s-terraform-state-whollyowned`
**Region**: `us-east-1`
**Versioning**: Enabled (90-day retention for old versions)
**Encryption**: AES256 server-side encryption
**Public Access**: Blocked (all public access denied)

### DynamoDB Table

```hcl
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "n2s-terraform-state-whollyowned-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "tfstate-backend"
    Purpose      = "Terraform state locking for whollyowned account"
  }
}
```

**Table Name**: `n2s-terraform-state-whollyowned-lock`
**Billing Mode**: Pay-per-request (no provisioned capacity)
**Hash Key**: `LockID` (String)

**Purpose**: Prevents concurrent Terraform runs from corrupting state files.

---

## Variables

### Required Variables

None - all values are hardcoded for the whollyowned account.

### Optional Variables

```hcl
variable "bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform state"
  default     = "n2s-terraform-state-whollyowned"
}

variable "dynamodb_table_name" {
  type        = string
  description = "DynamoDB table name for state locking"
  default     = "n2s-terraform-state-whollyowned-lock"
}

variable "lifecycle_noncurrent_days" {
  type        = number
  description = "Days to retain old state file versions"
  default     = 90
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
output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket name for Terraform state"
}

output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "S3 bucket ARN"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_lock.name
  description = "DynamoDB table name for state locking"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.terraform_lock.arn
  description = "DynamoDB table ARN"
}

output "backend_config" {
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    region         = aws_s3_bucket.terraform_state.region
    dynamodb_table = aws_dynamodb_table.terraform_lock.name
    encrypt        = true
  }
  description = "Backend configuration for use in other layers"
}
```

---

## Authentication & Permissions

### Initial Deployment

**Authentication**: Assumes `tfstate-terraform-role` (via SSO or GitHub Actions)

**AWS CLI Profile Setup** (for SSO admin manual deployment):

```bash
# Use whollyowned-admin SSO profile
aws sso login --profile whollyowned-admin

# Set environment variable for Terraform
export AWS_PROFILE=whollyowned-admin
```

**Alternative**: Assume `tfstate-terraform-role` directly (for GitHub Actions):

```bash
# GitHub Actions uses OIDC to assume role automatically
# No manual setup needed for CI/CD
```

**Required Permissions** (via `tfstate-terraform-role` from RBAC layer):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
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
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::n2s-terraform-state-whollyowned",
        "arn:aws:s3:::n2s-terraform-state-whollyowned/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTable",
        "dynamodb:TagResource",
        "dynamodb:UntagResource"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/n2s-terraform-state-whollyowned-lock"
    }
  ]
}
```

**Provider Configuration**:

```hcl
# provider.tf
provider "aws" {
  region = "us-east-1"

  # Optional: Assume tfstate-terraform-role (for GitHub Actions)
  # assume_role {
  #   role_arn     = "arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/tfstate-terraform-role"
  #   session_name = "terraform-tfstate-backend"
  # }
}
```

**No Cross-Account Access**: This layer does NOT require access to the management account.

---

## State Management

### Initial State (Local)

This layer **cannot use remote state initially** (bootstrap problem: the backend doesn't exist yet).

```hcl
# backend.tf (initially commented out)
# terraform {
#   backend "s3" {
#     bucket         = "n2s-terraform-state-whollyowned"
#     key            = "whollyowned/tfstate-backend.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-whollyowned-lock"
#     encrypt        = true
#   }
# }
```

### Migration to Remote State (After Deployment)

After the S3 bucket and DynamoDB table are created, this layer can migrate to remote state:

```bash
cd whollyowned/tfstate-backend
# Uncomment backend.tf
terraform init -migrate-state
# Answer "yes" to migrate local state to S3
```

**Result**: `tfstate-backend.tfstate` now stored in S3 (self-hosted backend).

---

## Deployment

### Prerequisites

1. RBAC layer deployed (IAM roles and OIDC provider exist)
2. AWS CLI configured with whollyowned SSO profile
3. All other whollyowned layers working with local state

### Step 1: Initialize Terraform

```bash
cd whollyowned/tfstate-backend
terraform init
```

**Expected Output**: Local backend initialized (no S3 backend yet)

### Step 2: Review Plan

```bash
terraform plan
```

**Expected Resources**:
- 1 S3 bucket
- 1 S3 bucket versioning configuration
- 1 S3 bucket encryption configuration
- 1 S3 bucket lifecycle configuration
- 1 S3 bucket public access block configuration
- 1 DynamoDB table

**Total**: 6 resources

### Step 3: Apply

```bash
terraform apply
```

**Timeline**: ~1-2 minutes

### Step 4: Verify Resources

```bash
# Verify S3 bucket
aws s3 ls s3://n2s-terraform-state-whollyowned --profile whollyowned-admin
# Expected: Empty (no state files yet)

# Verify bucket versioning
aws s3api get-bucket-versioning \
  --bucket n2s-terraform-state-whollyowned \
  --profile whollyowned-admin
# Expected: Status: Enabled

# Verify bucket encryption
aws s3api get-bucket-encryption \
  --bucket n2s-terraform-state-whollyowned \
  --profile whollyowned-admin
# Expected: SSEAlgorithm: AES256

# Verify DynamoDB table
aws dynamodb describe-table \
  --table-name n2s-terraform-state-whollyowned-lock \
  --profile whollyowned-admin
# Expected: TableStatus: ACTIVE
```

### Step 5: Migrate Whollyowned Layers to Remote State

Now migrate all whollyowned layers (rbac, tfstate-backend, domains, sites) to S3:

```bash
# RBAC layer
cd whollyowned/rbac
# Uncomment backend.tf:
# terraform {
#   backend "s3" {
#     bucket         = "n2s-terraform-state-whollyowned"
#     key            = "whollyowned/rbac.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-whollyowned-lock"
#     encrypt        = true
#   }
# }
terraform init -migrate-state
# Answer "yes"

# Tfstate-backend layer (self-migration)
cd ../tfstate-backend
# Uncomment backend.tf (key = "whollyowned/tfstate-backend.tfstate")
terraform init -migrate-state

# Domains layer (if deployed)
cd ../domains
# Uncomment backend.tf (key = "whollyowned/domains.tfstate")
terraform init -migrate-state

# Sites layer (if deployed)
cd ../sites
# Uncomment backend.tf (key = "whollyowned/sites.tfstate")
terraform init -migrate-state
```

### Step 6: Verify Remote State

```bash
# List all state files in S3
aws s3 ls s3://n2s-terraform-state-whollyowned/whollyowned/ --profile whollyowned-admin
# Expected:
# rbac.tfstate
# tfstate-backend.tfstate
# domains.tfstate (if deployed)
# sites.tfstate (if deployed)

# Verify state file versions
aws s3api list-object-versions \
  --bucket n2s-terraform-state-whollyowned \
  --prefix whollyowned/ \
  --profile whollyowned-admin
```

### Step 7: Clean Up Local State Files

```bash
# After verifying remote state works, delete local state files
cd whollyowned
rm rbac/terraform.tfstate*
rm tfstate-backend/terraform.tfstate*
rm domains/terraform.tfstate* 2>/dev/null  # If deployed
rm sites/terraform.tfstate* 2>/dev/null    # If deployed
```

**Important**: Only delete local state files AFTER verifying remote state migration succeeded.

---

## Post-Deployment Tasks

### 1. Test State Locking

Run two concurrent `terraform plan` operations in the same layer:

```bash
# Terminal 1
cd whollyowned/rbac
terraform plan

# Terminal 2 (while Terminal 1 is running)
cd whollyowned/rbac
terraform plan
```

**Expected**: Terminal 2 should wait with message: "Acquiring state lock. This may take a few moments..."

### 2. Test State Versioning

Make a change to a layer and apply:

```bash
cd whollyowned/rbac
# Make a trivial change (e.g., add a tag)
terraform apply

# Verify multiple versions in S3
aws s3api list-object-versions \
  --bucket n2s-terraform-state-whollyowned \
  --prefix whollyowned/rbac.tfstate \
  --profile whollyowned-admin
# Expected: Multiple VersionId entries
```

### 3. Proceed to Next Layer

**Next**: Deploy `whollyowned/domains` layer (Route53 zones + ACM certificates)

See [../domains/CLAUDE.md](../domains/CLAUDE.md)

---

## State File Organization

### Directory Structure in S3

```
s3://n2s-terraform-state-whollyowned/
└── whollyowned/
    ├── rbac.tfstate                  # Layer 0
    ├── tfstate-backend.tfstate       # Layer 1
    ├── domains.tfstate               # Layer 2
    └── sites.tfstate                 # Layer 3
```

**Naming Convention**: `whollyowned/<layer-name>.tfstate`

**Account Isolation**: Separate from management account state backend (`n2s-terraform-state-management`)

---

## Troubleshooting

### Error: Bucket Name Already Exists

**Symptoms**: `terraform apply` fails with "BucketAlreadyExists" or "BucketAlreadyOwnedByYou"

**Cause**: Bucket name is globally unique across all AWS accounts, or bucket already created

**Resolution**:

```bash
# Check if bucket exists in your account
aws s3 ls s3://n2s-terraform-state-whollyowned --profile whollyowned-admin
# If it exists, import into Terraform state
terraform import aws_s3_bucket.terraform_state n2s-terraform-state-whollyowned

# Re-run apply
terraform apply
```

### Error: State Migration Failed

**Symptoms**: `terraform init -migrate-state` fails or times out

**Cause**: Backend bucket doesn't exist, DynamoDB table missing, IAM permissions insufficient

**Resolution**:

```bash
# Verify backend resources exist
aws s3 ls s3://n2s-terraform-state-whollyowned --profile whollyowned-admin
aws dynamodb describe-table \
  --table-name n2s-terraform-state-whollyowned-lock \
  --profile whollyowned-admin

# Verify IAM permissions (should use tfstate-terraform-role or SSO admin)
aws sts get-caller-identity --profile whollyowned-admin

# If backend resources are missing, re-deploy tfstate-backend layer
cd whollyowned/tfstate-backend
terraform apply
```

### Error: State Locking Timeout

**Symptoms**: Terraform hangs with "Acquiring state lock" message for >5 minutes

**Cause**: Previous Terraform run failed without releasing lock, or DynamoDB table is down

**Resolution**:

```bash
# Check DynamoDB table status
aws dynamodb describe-table \
  --table-name n2s-terraform-state-whollyowned-lock \
  --profile whollyowned-admin

# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
# Lock ID shown in error message or in DynamoDB table
```

### Error: Cannot Read State File

**Symptoms**: `terraform plan` fails with "Error loading state: AccessDenied"

**Cause**: IAM permissions insufficient to read S3 bucket

**Resolution**:

Ensure your IAM user/role has state backend access policy (created by RBAC layer):

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::n2s-terraform-state-whollyowned",
    "arn:aws:s3:::n2s-terraform-state-whollyowned/*"
  ]
}
```

If using SSO admin, this should already be granted. If using GitHub Actions, verify `tfstate-terraform-role` has state backend access policy attached.

### Recovering from Accidental State Deletion

**Symptoms**: State file deleted from S3, Terraform thinks resources don't exist

**Resolution** (thanks to versioning):

```bash
# List all versions of state file
aws s3api list-object-versions \
  --bucket n2s-terraform-state-whollyowned \
  --prefix whollyowned/rbac.tfstate \
  --profile whollyowned-admin

# Copy previous version to latest
aws s3api copy-object \
  --bucket n2s-terraform-state-whollyowned \
  --copy-source n2s-terraform-state-whollyowned/whollyowned/rbac.tfstate?versionId=<VERSION_ID> \
  --key whollyowned/rbac.tfstate \
  --profile whollyowned-admin

# Verify recovery
cd whollyowned/rbac
terraform plan
# Should show no changes (infrastructure matches restored state)
```

---

## Cost Considerations

### S3 Costs

**Storage**: ~$0.023/GB per month (Standard tier)
- Typical state file size: 10-50 KB per layer
- Estimated monthly cost: <$0.01

**Requests**: ~$0.005 per 1,000 PUT requests, $0.0004 per 1,000 GET requests
- Terraform plan/apply generates ~5-10 requests per layer
- Estimated monthly cost (100 Terraform runs across all layers): <$0.01

**Versioning**: Old versions retained for 90 days, then deleted
- Estimated cost (10 versions × 50 KB × 4 layers): <$0.01

**Total S3 cost**: ~$0.10/month

### DynamoDB Costs

**Pay-per-request billing**: $1.25 per million write requests, $0.25 per million read requests
- Terraform state locking generates 2 requests per run (acquire + release)
- Estimated monthly cost (100 Terraform runs = 200 requests): <$0.01

**Storage**: $0.25/GB per month
- DynamoDB lock table stores only active locks (deleted after release)
- Estimated storage: <1 KB
- Estimated monthly cost: <$0.01

**Total DynamoDB cost**: ~$0.25/month

### Total Cost

**State backend total**: ~$0.35/month

**Included in**: Whollyowned account cost allocation (CostCenter: whollyowned)

---

## Security Considerations

### Encryption at Rest

- **S3 bucket**: AES256 server-side encryption (all state files encrypted automatically)
- **DynamoDB table**: AWS-managed encryption (default)

**State files contain sensitive data** (resource IDs, configuration values) - encryption is critical.

### Public Access Prevention

- **S3 bucket**: All public access blocked (block_public_acls, block_public_policy, etc.)
- **DynamoDB table**: No public endpoints (VPC-only access via AWS PrivateLink, optional)

### IAM Permissions

**Principle of Least Privilege**: Only grant state backend access to:
- Terraform execution roles (tfstate-terraform-role, domains-terraform-role, sites-terraform-role)
- Admin users via SSO (for manual Terraform runs)

**State Backend Access Policy** (attached to all Terraform roles by RBAC layer):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::n2s-terraform-state-whollyowned",
        "arn:aws:s3:::n2s-terraform-state-whollyowned/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/n2s-terraform-state-whollyowned-lock"
    }
  ]
}
```

### State File Versioning

- **Accidental deletion protection**: Versioning enabled, old versions retained for 90 days
- **Recovery procedure**: Restore previous version from S3
- **Security risk**: Old versions may contain outdated secrets (rotate secrets, then expire old versions)

### Audit Trail

- **CloudTrail**: All S3 and DynamoDB API calls logged
- **Monitor for**: Unauthorized state file access, unexpected state modifications, state lock manipulation

---

## Disaster Recovery

### Backup Strategy

**Primary**: S3 versioning (automatic, 90-day retention)

**Secondary** (optional): Cross-region replication to separate bucket

```hcl
# Future enhancement: replicate to us-west-2 for disaster recovery
resource "aws_s3_bucket_replication_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.terraform_state_replica.arn
      storage_class = "STANDARD_IA"
    }
  }
}
```

### Recovery Scenarios

**Scenario 1: Accidental State Deletion**
- **Recovery**: Restore from S3 version (see Troubleshooting section)
- **RPO**: 0 (immediate recovery)
- **RTO**: <5 minutes

**Scenario 2: S3 Bucket Deleted**
- **Prevention**: S3 bucket deletion requires two steps (empty bucket, then delete)
- **Recovery**: Re-create bucket, restore state files from backups
- **RPO**: Depends on backup frequency
- **RTO**: <30 minutes

**Scenario 3: State Corruption**
- **Recovery**: Restore from previous version, verify with `terraform plan`
- **RPO**: Depends on version age (max 90 days)
- **RTO**: <10 minutes

**Scenario 4: DynamoDB Table Deleted**
- **Impact**: Terraform state locking disabled (no state access corruption)
- **Recovery**: Re-create table with same name (Terraform will automatically use it)
- **RTO**: <5 minutes

---

## References

### Related Layers

- [../CLAUDE.md](../CLAUDE.md) - Whollyowned account overview
- [../rbac/CLAUDE.md](../rbac/CLAUDE.md) - RBAC layer (creates IAM roles)
- [../domains/CLAUDE.md](../domains/CLAUDE.md) - Next layer (domains)
- [../../management/tfstate-backend/CLAUDE.md](../../management/tfstate-backend/CLAUDE.md) - Management state backend (similar pattern)

### AWS Documentation

- [Terraform S3 Backend](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [S3 Bucket Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [DynamoDB State Locking](https://www.terraform.io/docs/language/settings/backends/s3.html#dynamodb-state-locking)
- [S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html)

---

**Layer**: 1 (Tfstate Backend)
**Account**: noise2signal-llc-whollyowned
**Last Updated**: 2026-01-26
