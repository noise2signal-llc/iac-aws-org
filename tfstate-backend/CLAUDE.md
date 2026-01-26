# Layer 2: Tfstate Backend

## Layer Purpose

This layer provisions the **Terraform state backend infrastructure** - an S3 bucket for remote state storage and a DynamoDB table for state locking. This layer can be deployed last (after all other layers are working with local state) and then all layers migrate their state files to the shared backend.

**Deployment Order**: Layer 2 (can be deployed last, after RBAC and before/after other layers)

## Scope & Responsibilities

### In Scope
✅ **S3 State Backend Bucket**
- Centralized storage for all Terraform state files
- Versioning enabled for state recovery
- Encryption at rest (AES256)
- Lifecycle policies for old version cleanup
- Public access blocking

✅ **DynamoDB State Lock Table**
- Prevents concurrent Terraform operations
- Pay-per-request billing (cost-effective)
- Single table for all layer state locks

✅ **Bucket Policies**
- Restrict access to Terraform execution roles only
- Enforce encryption for all objects

### Out of Scope
❌ IAM roles (managed in `rbac` layer)
❌ Service Control Policies (managed in `scp` layer)
❌ Application resources (managed in domain-specific layers)

## Architecture Context

### Layer Dependencies

```
Layer 0: scp (bootstrap)
    ↓
Layer 1: rbac (IAM roles)
    ↓
Layer 2: tfstate-backend (S3 + DynamoDB) ← YOU ARE HERE
    ↓
Layer 3: domains (Route53 + ACM)
    ↓
Layer 4: sites (S3 + CloudFront + DNS records)
```

### State Management

**State Storage**: Local state file (`.tfstate` in this directory, gitignored)

**Why Local State**:
- This layer creates the S3 backend - can't use itself for state storage initially
- Local state is the bootstrap approach for the state backend

**State Migration**: After this layer is deployed, ALL layers (including this one) can migrate to remote state

**Deployment Role**: `tfstate-backend-terraform-role` (from RBAC layer)

## State File Organization

Once deployed, the S3 bucket will store state files for all layers:

```
s3://noise2signal-terraform-state/
└── noise2signal/
    ├── scp.tfstate                 # SCP layer state
    ├── rbac.tfstate                # RBAC layer state
    ├── tfstate-backend.tfstate     # This layer's state (after migration)
    ├── domains.tfstate             # Domains layer state
    └── sites.tfstate               # Sites layer state
```

**State Key Pattern**: `noise2signal/{layer-name}.tfstate`

**Future Multi-Tenancy**: Client work can use separate prefixes (e.g., `client-acme/sites.tfstate`)

## Resources Managed

### 1. S3 State Backend Bucket

Centralized storage for all Terraform state files.

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name  # Default: "noise2signal-terraform-state"

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "tfstate-backend-layer"
    Purpose     = "terraform-state-backend"
    Layer       = "2-tfstate-backend"
  }
}

# Versioning for state recovery
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for old versions (cost control)
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90  # Delete versions older than 90 days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
```

### 2. S3 Bucket Policy

Restrict access to Terraform execution roles only.

```hcl
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceSSLOnly"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowTerraformRoles"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/scp-terraform-role",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/rbac-terraform-role",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/tfstate-backend-terraform-role",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/domains-terraform-role",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sites-terraform-role",
          ]
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
```

### 3. DynamoDB State Lock Table

Prevents concurrent Terraform operations on the same state file.

```hcl
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.state_lock_table_name  # Default: "noise2signal-terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"  # Cost-effective for infrequent operations
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "tfstate-backend-layer"
    Purpose     = "terraform-state-locking"
    Layer       = "2-tfstate-backend"
  }
}
```

**Note**: No need for point-in-time recovery (PITR) - the table only stores ephemeral lock records.

## Terraform Configuration

### Backend Configuration (Initially Commented)

```hcl
# backend.tf
# This layer uses LOCAL state initially
# After deployment, uncomment and migrate state to S3

# terraform {
#   backend "s3" {
#     bucket         = "noise2signal-terraform-state"
#     key            = "noise2signal/tfstate-backend.tfstate"
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

  # Assume tfstate-backend-terraform-role from RBAC layer
  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/tfstate-backend-terraform-role"
    session_name = "terraform-tfstate-backend-session"
  }

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "tfstate-backend-layer"
      Layer       = "2-tfstate-backend"
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

variable "aws_account_id" {
  description = "AWS account ID (for IAM role ARNs)"
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state storage"
  type        = string
  default     = "noise2signal-terraform-state"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.state_bucket_name))
    error_message = "Bucket name must be lowercase alphanumeric with hyphens only."
  }
}

variable "state_lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "noise2signal-terraform-state-lock"
}

variable "state_version_retention_days" {
  description = "Number of days to retain old state file versions"
  type        = number
  default     = 90
}
```

### Outputs

```hcl
# outputs.tf
output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.terraform_state.arn
}

output "state_bucket_region" {
  description = "S3 bucket region"
  value       = aws_s3_bucket.terraform_state.region
}

output "state_lock_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_lock.id
}

output "state_lock_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.terraform_lock.arn
}

output "backend_config" {
  description = "Backend configuration for other layers"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.terraform_lock.id
    encrypt        = true
  }
}
```

## Deployment Process

### Prerequisites
- SCP layer deployed (Layer 0)
- RBAC layer deployed (Layer 1) - `tfstate-backend-terraform-role` exists
- AWS CLI configured
- Terraform 1.5+ installed

### Initial Deployment

1. **Navigate to tfstate-backend layer**
   ```bash
   cd /workspace/tfstate-backend
   ```

2. **Configure variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with AWS account ID and bucket name
   ```

3. **Initialize Terraform (local state)**
   ```bash
   terraform init
   # Should use local state (no backend configured yet)
   ```

4. **Plan infrastructure**
   ```bash
   terraform plan -out=tfplan
   # Review: S3 bucket, DynamoDB table, bucket policy
   ```

5. **Apply tfstate-backend resources**
   ```bash
   terraform apply tfplan
   ```

6. **Verify resources created**
   ```bash
   # Check S3 bucket
   aws s3 ls | grep noise2signal-terraform-state

   # Check DynamoDB table
   aws dynamodb describe-table --table-name noise2signal-terraform-state-lock
   ```

7. **Migrate this layer's state to S3** (optional, recommended)
   ```bash
   # Uncomment backend.tf configuration
   terraform init -migrate-state
   # Confirm migration
   # Local terraform.tfstate file can now be deleted
   ```

## State Migration for Other Layers

After this layer is deployed, migrate all other layers to remote state.

### Migration Process (Per Layer)

Example for domains layer:

```bash
cd /workspace/domains

# Uncomment backend.tf configuration
# Verify backend config matches:
#   bucket         = "noise2signal-terraform-state"
#   key            = "noise2signal/domains.tfstate"
#   region         = "us-east-1"
#   dynamodb_table = "noise2signal-terraform-state-lock"

# Migrate state
terraform init -migrate-state

# Verify remote state
terraform state list

# Remove local state file (now stored in S3)
rm terraform.tfstate terraform.tfstate.backup
```

Repeat for: `scp`, `rbac`, `tfstate-backend`, `domains`, `sites`

### Verification After Migration

```bash
# List state files in S3
aws s3 ls s3://noise2signal-terraform-state/noise2signal/

# Should show:
# scp.tfstate
# rbac.tfstate
# tfstate-backend.tfstate
# domains.tfstate
# sites.tfstate
```

## Security Considerations

### State File Security
- State files contain sensitive data (resource IDs, configurations)
- S3 bucket encryption is MANDATORY (enforced)
- Bucket policy restricts access to Terraform roles only
- Versioning enabled for recovery from accidental deletions
- Public access blocked at bucket level

### Bucket Policy Enforcement
- SSL/TLS required for all operations (HTTP blocked)
- Only specific IAM roles can access state files
- No wildcards in principal ARNs

### DynamoDB Lock Security
- Locks are ephemeral (no sensitive data)
- Pay-per-request prevents cost issues from stuck locks
- IAM policies control lock operations

### State File Versioning
- Previous versions retained for 90 days (configurable)
- Allows rollback if state corruption occurs
- Old versions automatically cleaned up (cost control)

## Dependencies

### Upstream Dependencies
- `scp` layer (Layer 0) - Allows S3 and DynamoDB services
- `rbac` layer (Layer 1) - Provides `tfstate-backend-terraform-role`

### Downstream Dependencies
- All layers use this backend for remote state storage
- State locking prevents concurrent operations

## Cost Estimates

**Monthly costs (low usage)**:
- S3 bucket storage: ~$0.10 (state files are small, <1MB typically)
- S3 requests: ~$0.01 (GET/PUT operations during terraform runs)
- DynamoDB: ~$0.25 (PAY_PER_REQUEST, minimal lock operations)
- **Total: ~$0.36/month**

**Versioning impact**: Minimal (old versions are small, cleaned up after 90 days)

## Testing & Validation

### Post-Deployment Checks
- [ ] S3 bucket exists with versioning enabled
- [ ] S3 bucket is encrypted (AES256)
- [ ] S3 bucket blocks all public access
- [ ] DynamoDB table exists and is active
- [ ] Bucket policy allows Terraform roles
- [ ] Lifecycle policy configured for old versions

### Validation Commands

```bash
# Verify S3 bucket
aws s3api head-bucket --bucket noise2signal-terraform-state

# Check encryption
aws s3api get-bucket-encryption --bucket noise2signal-terraform-state

# Check versioning
aws s3api get-bucket-versioning --bucket noise2signal-terraform-state

# Check public access block
aws s3api get-public-access-block --bucket noise2signal-terraform-state

# Verify DynamoDB table
aws dynamodb describe-table --table-name noise2signal-terraform-state-lock

# Test state locking (run terraform plan in any layer, check DynamoDB)
aws dynamodb scan --table-name noise2signal-terraform-state-lock
```

### Testing State Locking

```bash
# In one terminal
cd /workspace/domains
terraform plan  # Acquires lock

# In another terminal (while plan is running)
cd /workspace/domains
terraform plan  # Should wait for lock or timeout

# Verify lock exists in DynamoDB
aws dynamodb scan --table-name noise2signal-terraform-state-lock
```

## Maintenance & Updates

### Regular Maintenance
- Monitor S3 bucket size (should remain small)
- Review old state versions quarterly (check lifecycle policy)
- Verify bucket policy includes new Terraform roles (if layers added)
- Check DynamoDB lock table for stuck locks (rare)

### Clearing Stuck Locks

If a lock is stuck (Terraform crashed without releasing):

```bash
# List locks
aws dynamodb scan --table-name noise2signal-terraform-state-lock

# Force unlock from Terraform
cd /workspace/{layer-with-stuck-lock}
terraform force-unlock <LOCK_ID>

# Or manually delete from DynamoDB (use with caution)
aws dynamodb delete-item \
  --table-name noise2signal-terraform-state-lock \
  --key '{"LockID": {"S": "{LOCK_ID}"}}'
```

### Bucket Name Changes

**Warning**: Changing bucket name requires careful state migration:

1. Create new bucket with Terraform
2. Copy state files from old bucket to new
3. Update backend configuration in all layers
4. Re-initialize all layers with new backend
5. Delete old bucket after verification

**Recommendation**: Avoid renaming unless absolutely necessary.

## Disaster Recovery

### State File Recovery

**Accidental Deletion**:
```bash
# List versions
aws s3api list-object-versions --bucket noise2signal-terraform-state --prefix noise2signal/domains.tfstate

# Restore specific version
aws s3api get-object \
  --bucket noise2signal-terraform-state \
  --key noise2signal/domains.tfstate \
  --version-id <VERSION_ID> \
  domains.tfstate.recovered
```

**State Corruption**:
```bash
# Download previous version from S3
aws s3 cp s3://noise2signal-terraform-state/noise2signal/domains.tfstate ./domains.tfstate.backup

# Review and restore if needed
cp domains.tfstate.backup domains.tfstate
terraform state list  # Verify
```

### Complete Backend Loss

If S3 bucket is deleted entirely:
1. All layers have local state backups (`.tfstate.backup` files if not deleted)
2. Redeploy this layer to recreate bucket
3. Upload backed-up state files to S3
4. Re-initialize all layers

**Prevention**: Enable S3 MFA Delete (optional, high security environments)

## Troubleshooting

### State Locking Timeout
**Symptoms**: "Error acquiring state lock" after 10+ seconds

**Causes**:
- Previous Terraform run crashed without releasing lock
- Concurrent Terraform operations on same state file

**Resolution**:
```bash
# Check for active locks
aws dynamodb scan --table-name noise2signal-terraform-state-lock

# Force unlock (use with caution, ensure no other operations running)
terraform force-unlock <LOCK_ID>
```

### Backend Initialization Fails
**Symptoms**: "Error configuring the backend" during `terraform init`

**Causes**:
- S3 bucket doesn't exist
- DynamoDB table doesn't exist
- IAM role lacks permissions
- Wrong bucket name in backend configuration

**Resolution**:
```bash
# Verify bucket exists
aws s3 ls s3://noise2signal-terraform-state

# Verify DynamoDB table exists
aws dynamodb describe-table --table-name noise2signal-terraform-state-lock

# Check IAM permissions
aws sts get-caller-identity  # Verify role assumed correctly
```

### State File Not Found
**Symptoms**: "No state file found" after migration

**Causes**:
- Wrong state key in backend configuration
- State file not uploaded to S3

**Resolution**:
```bash
# List state files in S3
aws s3 ls s3://noise2signal-terraform-state/noise2signal/

# Verify backend configuration matches state key
cat backend.tf
```

## Future Enhancements

- Multi-region S3 replication (disaster recovery)
- S3 MFA Delete protection (prevent accidental state deletion)
- CloudWatch alarms for state file changes
- State file audit logging (S3 access logs to separate bucket)
- Terraform Cloud migration (centralized state management)

## References

- [Terraform S3 Backend](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [DynamoDB State Locking](https://www.terraform.io/docs/language/settings/backends/s3.html#dynamodb-state-locking)
- [State Locking Best Practices](https://www.terraform.io/docs/language/state/locking.html)
