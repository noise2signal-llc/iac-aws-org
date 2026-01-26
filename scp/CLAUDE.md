# Layer 0: Service Control Policies (SCP)

## Layer Purpose

This layer defines **Service Control Policies** that constrain the AWS account to only the services actively used by Noise2Signal LLC infrastructure. This is the true bootstrap layer and serves as a security boundary - when new AWS services are needed, they must first be enabled here.

**Deployment Order**: Layer 0 (deployed first, before any other infrastructure)

## Scope & Responsibilities

### In Scope
✅ **Service Control Policies**
- Define allowed AWS services (S3, Route53, CloudFront, ACM, IAM, DynamoDB, STS)
- Block unused services to reduce attack surface
- Enforce regional restrictions (primarily us-east-1)
- Prevent accidental resource creation in unauthorized services

✅ **Account-Level Service Constraints**
- Explicit allow-list of services
- Region restrictions for global services
- Cost control through service limitations

### Out of Scope
❌ IAM roles and policies (managed in `rbac` layer)
❌ State backend infrastructure (managed in `tfstate-backend` layer)
❌ Application resources (managed in domain-specific layers)

## Architecture Context

### Layer Dependencies

```
Layer 0: scp (bootstrap - no dependencies)
    ↓
Layer 1: rbac (IAM roles)
    ↓
Layer 2: tfstate-backend (S3 + DynamoDB) [optional, deployed last]
    ↓
Layer 3: domains (Route53 + ACM)
    ↓
Layer 4: sites (S3 + CloudFront + DNS records)
```

### State Management

**State Storage**: Local state file (`.tfstate` in this directory, gitignored)

**Why Local State**:
- SCP is the foundational layer - no S3 backend exists yet
- SCP changes are infrequent and require elevated permissions
- Can be migrated to remote state after `tfstate-backend` layer is deployed

**Deployment Credentials**: AWS administrator credentials (manual/temporary)

**Future State Migration**: After `tfstate-backend` layer exists, uncomment `backend.tf` and run `terraform init -migrate-state`

## Current Allowed Services

Based on Noise2Signal LLC infrastructure requirements:

### Core AWS Services
- **IAM**: Identity and Access Management (roles, policies, OIDC provider)
- **STS**: Security Token Service (role assumption)
- **Organizations**: AWS Organizations (for SCP management itself)

### State & Data Storage
- **S3**: Simple Storage Service (state backend, website hosting)
- **DynamoDB**: State locking table

### DNS & Certificates
- **Route53**: DNS hosting and domain management
- **ACM**: AWS Certificate Manager (SSL/TLS certificates)

### Content Delivery
- **CloudFront**: CDN for static site distribution

### Observability (Future)
- **CloudWatch**: Logs and metrics (when needed)

### Regional Constraints
- **Primary Region**: us-east-1
- **ACM for CloudFront**: us-east-1 (required)
- **Global Services**: CloudFront, Route53, IAM (region-agnostic)

## Resources Managed

### Service Control Policy Structure

```hcl
# SCP allowing only required services
resource "aws_organizations_policy" "service_allowlist" {
  name        = "noise2signal-service-allowlist"
  description = "Restrict account to services actively used by infrastructure"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRequiredServices"
        Effect = "Allow"
        Action = [
          # Core services
          "iam:*",
          "sts:*",
          "organizations:*",

          # Storage
          "s3:*",
          "dynamodb:*",

          # DNS & Certificates
          "route53:*",
          "acm:*",

          # CDN
          "cloudfront:*",

          # Future: Add services as needed
          # "cloudwatch:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "EnforceRegion"
        Effect = "Deny"
        NotAction = [
          # Global services (no region constraint)
          "iam:*",
          "organizations:*",
          "route53:*",
          "cloudfront:*",
          "sts:*",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["us-east-1"]
          }
        }
      }
    ]
  })
}

# Attach SCP to account or organizational unit
resource "aws_organizations_policy_attachment" "account" {
  policy_id = aws_organizations_policy.service_allowlist.id
  target_id = var.account_id  # AWS account ID or OU ID
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
#     key            = "noise2signal/scp.tfstate"
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

  # SCP layer uses admin credentials (no assumed role)
  # This is the bootstrap layer deployed before RBAC exists

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "scp-layer"
      Layer       = "0-scp"
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

variable "account_id" {
  description = "AWS account ID or organizational unit ID for SCP attachment"
  type        = string
}

variable "allowed_regions" {
  description = "List of allowed AWS regions for service usage"
  type        = list(string)
  default     = ["us-east-1"]
}
```

### Outputs

```hcl
# outputs.tf
output "scp_policy_id" {
  description = "Service Control Policy ID"
  value       = aws_organizations_policy.service_allowlist.id
}

output "scp_policy_arn" {
  description = "Service Control Policy ARN"
  value       = aws_organizations_policy.service_allowlist.arn
}

output "allowed_services" {
  description = "List of allowed AWS services"
  value = [
    "iam",
    "sts",
    "organizations",
    "s3",
    "dynamodb",
    "route53",
    "acm",
    "cloudfront",
  ]
}
```

## Deployment Process

### Prerequisites
- AWS account created
- AWS Organizations enabled (or standalone account)
- AWS CLI configured with **administrator credentials**
- Terraform 1.5+ installed

### Initial Deployment

1. **Configure account ID**
   ```bash
   cd /workspace/scp
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your AWS account ID
   ```

2. **Initialize Terraform (local state)**
   ```bash
   terraform init
   ```

3. **Plan infrastructure**
   ```bash
   terraform plan -out=tfplan
   # Review: SCP policy creation and attachment
   ```

4. **Apply SCP constraints**
   ```bash
   terraform apply tfplan
   ```

5. **Verify SCP attachment**
   ```bash
   aws organizations list-policies --filter SERVICE_CONTROL_POLICY
   ```

### Adding New Services

When infrastructure requires a new AWS service (e.g., Lambda, CloudWatch):

1. **Update SCP policy** in `main.tf` to add service actions
2. **Plan and review** changes
3. **Apply** updated SCP
4. **Deploy** infrastructure using the new service in appropriate layer

**Important**: Never add services speculatively - only add when actively needed.

## Security Considerations

### Defense in Depth
- SCPs act as a security boundary even if IAM policies are misconfigured
- Principle of least privilege at the account level
- Reduces blast radius of compromised credentials

### Service Constraints
- Explicit allow-list approach (deny by default)
- Regional restrictions prevent accidental multi-region deployments
- Cost control through service limitations

### SCP Limitations
- SCPs don't apply to the root user (use root user sparingly)
- SCPs apply to all principals including admins (test carefully)
- Can't use SCPs to grant permissions, only restrict

### Credential Management
- SCP deployment requires admin credentials initially
- Consider creating `scp-terraform-role` in RBAC layer for future updates
- Rotate admin credentials after initial bootstrap

## Dependencies

### Upstream Dependencies
- **None** - This is Layer 0 (bootstrap layer)

### Downstream Dependencies
- All other layers benefit from SCP constraints
- RBAC layer creates IAM roles within SCP boundaries
- Application layers can only use SCP-allowed services

## Cost Estimates

**Service Control Policies**: Free (no AWS charges for SCPs)

**Time Cost**: ~5 minutes initial setup, infrequent updates

## Testing & Validation

### Post-Deployment Checks
- [ ] SCP policy exists in AWS Organizations
- [ ] SCP is attached to correct account/OU
- [ ] Allowed services are accessible (test with IAM role assumption)
- [ ] Blocked services return permission denied (optional negative test)

### Validation Commands

```bash
# List SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Describe SCP policy
aws organizations describe-policy --policy-id <POLICY_ID>

# List SCP attachments
aws organizations list-targets-for-policy --policy-id <POLICY_ID>

# Test allowed service (should work)
aws s3 ls

# Test blocked service (should fail with permission error)
# aws ec2 describe-instances  # Example of blocked service
```

## Maintenance & Updates

### Regular Maintenance
- Review SCP quarterly to ensure alignment with infrastructure
- Remove services that are no longer used
- Update regional restrictions if multi-region expansion needed

### Adding Services
When a new layer requires additional AWS services:
1. Update `main.tf` to add service to allowed list
2. Apply changes with `terraform apply`
3. Proceed with infrastructure deployment in other layers

### Emergency SCP Bypass
If SCP blocks critical operations:
1. Use AWS root user (SCPs don't apply to root)
2. Or temporarily detach SCP, perform operation, reattach
3. Update SCP to allow required operation going forward

## Troubleshooting

### Access Denied Errors in Other Layers
**Symptoms**: Terraform operations fail with "Access Denied" despite correct IAM policies

**Cause**: Service not allowed in SCP

**Resolution**:
1. Identify required service from error message
2. Add service to SCP allowed list
3. Apply SCP changes
4. Retry infrastructure deployment

### SCP Attachment Failures
**Symptoms**: SCP policy created but attachment fails

**Cause**: Invalid account ID or OU ID

**Resolution**:
```bash
# Verify account ID
aws sts get-caller-identity

# Verify OU structure (if using Organizations)
aws organizations list-accounts
```

### Regional Restriction Issues
**Symptoms**: Operations fail in specific regions

**Cause**: Region not in allowed list

**Resolution**:
Update `allowed_regions` variable and apply changes

## Future Enhancements

- CloudWatch Logs for audit trail (when logging layer added)
- Lambda support (if serverless functions needed)
- SNS/SES for notifications (if alerting needed)
- AWS Config for compliance monitoring
- Additional regional support if multi-region expansion occurs

## References

- [AWS Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [SCP Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_strategies.html)
- [Testing SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)
