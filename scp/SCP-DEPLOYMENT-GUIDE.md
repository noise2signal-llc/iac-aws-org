# Service Control Policy Deployment Guide

## Overview

This guide walks through deploying the Website Hosting SCP to constrain your AWS account to only the services and actions needed for static website hosting via Terraform.

**Purpose**: Security AND cost guardrails - only allow services actively used for website hosting.

---

## Prerequisites

### Step 1: Enable AWS Organizations (If Not Already)

Even with a single account, you need AWS Organizations to use SCPs.

**Via AWS Console**:
1. Navigate to AWS Organizations console
2. Click "Create organization"
3. Confirm your account becomes the management account
4. Organization created (no additional cost)

**Via AWS CLI**:
```bash
aws organizations create-organization

# Verify organization created
aws organizations describe-organization
```

**Result**: Your account is now in an organization and can have SCPs attached.

---

## SCP Policy Summary

**File**: `/workspace/scp/scp-policy-website-hosting.json`

### Allowed Services (Specific Actions Only)

| Service | Purpose | Example Actions |
|---------|---------|----------------|
| **STS** | Role assumption | AssumeRole, GetCallerIdentity |
| **IAM** | RBAC layer | CreateRole, CreatePolicy, AttachRolePolicy |
| **S3** | State backend + websites | CreateBucket, PutObject, PutBucketPolicy |
| **DynamoDB** | State locking | CreateTable, GetItem, PutItem |
| **Route53** | DNS zones | CreateHostedZone, ChangeResourceRecordSets |
| **ACM** | SSL certificates | RequestCertificate, DescribeCertificate |
| **CloudFront** | CDN | CreateDistribution, CreateOriginAccessControl |
| **Organizations** | SCP management | DescribeOrganization, CreatePolicy |

### Regional Restrictions

**Allowed US Regions**:
- us-east-1 (required for ACM/CloudFront)
- us-east-2
- us-west-1
- us-west-2

**Blocked**: All non-US regions (EU, Asia, etc.)

**Exception**: Global services (IAM, CloudFront, Route53, ACM) work regardless of region.

### Denied Services

**ALL other AWS services are blocked**, including:
- EC2, ECS, EKS (compute)
- RDS, Aurora (databases)
- Lambda (serverless)
- SES, SNS, SQS (messaging)
- CloudWatch Logs (logging)
- And 200+ other services

**To add a service**: Update this SCP first, apply, then deploy infrastructure.

---

## Deployment Options

### Option A: Manual Deployment (AWS Console)

1. **Navigate to AWS Organizations Console**
   - Go to: https://console.aws.amazon.com/organizations/

2. **Create SCP Policy**
   - Left menu: Policies → Service control policies
   - Click "Create policy"
   - Name: `WebsiteHostingOnly`
   - Description: `Restrict account to services needed for static website hosting`
   - Copy contents of `/workspace/scp/scp-policy-website-hosting.json`
   - Paste into policy editor
   - Click "Create policy"

3. **Attach SCP to Account**
   - Go to: Accounts
   - Select your account
   - Click "Policies" tab
   - Click "Attach"
   - Select `WebsiteHostingOnly`
   - Click "Attach policy"

4. **Verify SCP Applied**
   - Try creating a resource from a blocked service (e.g., EC2 instance)
   - Should receive "Access Denied" with SCP message

### Option B: Terraform Deployment (Recommended)

**File structure**:
```
scp/
├── CLAUDE.md
├── SCP-DEPLOYMENT-GUIDE.md          # This file
├── scp-policy-website-hosting.json  # Policy JSON
├── main.tf                          # Terraform resources (create this)
├── variables.tf
├── outputs.tf
├── provider.tf
└── backend.tf                       # Commented initially
```

**Create scp/main.tf**:
```hcl
# Read the SCP policy from JSON file
locals {
  scp_policy = file("${path.module}/scp-policy-website-hosting.json")
}

# Create the SCP policy
resource "aws_organizations_policy" "website_hosting" {
  name        = "WebsiteHostingOnly"
  description = "Restrict account to services needed for static website hosting (security + cost guardrails)"
  type        = "SERVICE_CONTROL_POLICY"
  content     = local.scp_policy

  tags = {
    Owner       = "Noise2Signal LLC"
    Terraform   = "true"
    ManagedBy   = "scp-layer"
    Layer       = "0-scp"
    Purpose     = "website-hosting-constraints"
  }
}

# Get the current AWS account ID
data "aws_caller_identity" "current" {}

# Attach SCP to the account
resource "aws_organizations_policy_attachment" "account" {
  policy_id = aws_organizations_policy.website_hosting.id
  target_id = data.aws_caller_identity.current.account_id
}
```

**Create scp/variables.tf**:
```hcl
variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}
```

**Create scp/outputs.tf**:
```hcl
output "scp_policy_id" {
  description = "Service Control Policy ID"
  value       = aws_organizations_policy.website_hosting.id
}

output "scp_policy_arn" {
  description = "Service Control Policy ARN"
  value       = aws_organizations_policy.website_hosting.arn
}

output "scp_policy_name" {
  description = "Service Control Policy name"
  value       = aws_organizations_policy.website_hosting.name
}

output "account_id" {
  description = "AWS account ID with SCP attached"
  value       = data.aws_caller_identity.current.account_id
}

output "allowed_services" {
  description = "List of allowed AWS services"
  value = [
    "sts",
    "iam",
    "s3",
    "dynamodb",
    "route53",
    "acm",
    "cloudfront",
    "organizations",
  ]
}

output "allowed_regions" {
  description = "List of allowed AWS regions"
  value = [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
  ]
}
```

**Create scp/provider.tf**:
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

  # SCP layer uses admin credentials (no assumed role)
  # This is Layer 0 - deployed before RBAC layer exists

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

**Create scp/backend.tf** (commented initially):
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

**Deploy via Terraform**:
```bash
cd /workspace/scp

# Initialize Terraform (local state)
terraform init

# Review SCP policy and resources
terraform plan -out=tfplan

# Apply SCP
terraform apply tfplan

# Verify outputs
terraform output
```

---

## Testing the SCP

### Test 1: Verify Allowed Services Work

```bash
# Should work: S3 (allowed)
aws s3 ls

# Should work: Route53 (allowed)
aws route53 list-hosted-zones

# Should work: IAM (allowed)
aws iam list-roles
```

### Test 2: Verify Blocked Services Fail

```bash
# Should FAIL: EC2 (blocked)
aws ec2 describe-instances
# Expected error: "Access Denied" with SCP policy name

# Should FAIL: RDS (blocked)
aws rds describe-db-instances
# Expected error: "Access Denied"

# Should FAIL: Lambda (blocked)
aws lambda list-functions
# Expected error: "Access Denied"
```

### Test 3: Verify Regional Restrictions

```bash
# Should work: S3 in us-east-1 (allowed region)
aws s3 ls --region us-east-1

# Should FAIL: S3 in eu-west-1 (blocked region)
aws s3 ls --region eu-west-1
# Expected error: "Access Denied"
```

### Test 4: Verify Root User Not Affected

**Important**: SCPs do NOT apply to the root user of the management account.

- Root user can still access all services (bypass SCP)
- This is intentional (emergency access)
- Recommendation: Use root user sparingly, enforce MFA

---

## Adding New Services (Future)

When you need to add a new AWS service (e.g., CloudWatch Logs, Lambda, SES):

### Step 1: Update SCP Policy

Edit `/workspace/scp/scp-policy-website-hosting.json`:

```json
{
  "Sid": "AllowCloudWatchForLogging",
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "logs:DescribeLogGroups",
    "logs:DescribeLogStreams"
  ],
  "Resource": "*"
}
```

### Step 2: Update DenyExpensiveServices Statement

Remove the new service from the `NotAction` list in the `DenyExpensiveServices` statement:

```json
{
  "Sid": "DenyExpensiveServices",
  "Effect": "Deny",
  "NotAction": [
    "sts:*",
    "iam:*",
    "organizations:*",
    "s3:*",
    "dynamodb:*",
    "route53:*",
    "acm:*",
    "cloudfront:*",
    "logs:*"  // Added
  ],
  "Resource": "*"
}
```

### Step 3: Apply Updated SCP

```bash
cd /workspace/scp

# Review changes
terraform plan

# Apply updated SCP
terraform apply
```

### Step 4: Deploy Infrastructure Using New Service

After SCP is updated, proceed with deploying infrastructure in other layers.

---

## SCP vs IAM Permissions

**Key Difference**: SCPs don't GRANT permissions, they RESTRICT them.

**How it works**:
1. IAM role has permissions (e.g., `s3:*`)
2. SCP restricts to subset (e.g., only specific S3 actions)
3. Effective permissions = IAM ∩ SCP (intersection)

**Example**:
- IAM role: `s3:*` (all S3 actions)
- SCP: `s3:GetObject, s3:PutObject` (only Get/Put)
- **Result**: Role can only Get/Put objects (SCP wins)

**Benefit**: Even if IAM policies are misconfigured (too permissive), SCP provides guardrails.

---

## Cost Control Benefits

### Services Blocked = Costs Prevented

**Expensive services blocked**:
- EC2 instances (compute costs)
- RDS databases (database costs)
- NAT Gateways (data transfer)
- ELB/ALB (load balancer costs)
- Fargate/EKS (container costs)

**How it prevents cost**:
- Can't accidentally create EC2 instance → No instance hours charged
- Can't create RDS database → No database costs
- Terraform apply fails if trying to use blocked service

**Example Scenario**:
1. Developer tries to add `aws_instance` resource in Terraform
2. `terraform apply` fails with "Access Denied" (SCP)
3. No EC2 instance created → **$0 cost** (prevented)

---

## Emergency SCP Bypass

If SCP blocks a critical operation:

### Option 1: Use Root User (Not Recommended)
- SCPs don't apply to root user of management account
- Can perform any operation
- **Only use in true emergencies**

### Option 2: Temporarily Detach SCP
```bash
# Get policy attachment ID
aws organizations list-policies-for-target --target-id <ACCOUNT_ID>

# Detach SCP
aws organizations detach-policy \
  --policy-id <POLICY_ID> \
  --target-id <ACCOUNT_ID>

# Perform critical operation

# Re-attach SCP
aws organizations attach-policy \
  --policy-id <POLICY_ID> \
  --target-id <ACCOUNT_ID>
```

### Option 3: Update SCP (Preferred)
If the operation is legitimate, update the SCP to allow it (add service).

---

## Monitoring SCP Denials

**CloudTrail Events**: SCPs generate "Access Denied" events in CloudTrail

**Query CloudTrail for SCP denials**:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AccessDenied \
  --max-results 50 \
  | jq '.Events[] | select(.ErrorCode == "AccessDenied")'
```

**Set up CloudWatch Alarm** (future enhancement):
- Monitor for SCP denial events
- Alert if unusual spike (potential attack or misconfiguration)

---

## Troubleshooting

### Issue: "Organizations is not enabled"

**Cause**: Account is not part of an AWS Organization

**Resolution**:
```bash
aws organizations create-organization
```

### Issue: "Access Denied" when applying SCP via Terraform

**Cause**: Current IAM user/role doesn't have Organizations permissions

**Resolution**: Use root user or IAM user with `AdministratorAccess` for initial SCP deployment

### Issue: All operations fail after applying SCP

**Cause**: SCP too restrictive, blocking required actions

**Resolution**:
1. Check SCP policy JSON for errors
2. Verify `NotAction` lists in Deny statements
3. Temporarily detach SCP and debug
4. Update SCP to allow required actions

### Issue: Regional restriction blocking global services

**Cause**: Global services (IAM, CloudFront, Route53) included in regional Deny statement

**Resolution**: Verify `NotAction` in `EnforceUSRegions` statement includes global services

---

## References

- [AWS Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [SCP Syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_syntax.html)
- [Testing SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)
- [AWS Organizations Setup](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_org_create.html)

---

**Last Updated**: 2026-01-26
**Maintained By**: Noise2Signal LLC Infrastructure Team
