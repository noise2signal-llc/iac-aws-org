# Management Account - SCP Layer (Service Control Policies)

## Purpose

The **SCP layer** defines **Service Control Policies** that constrain AWS accounts in the organization to only the services actively used by Noise2Signal LLC infrastructure. SCPs act as security boundaries applied at the organizational unit (OU) level.

**This is Layer 2** - deployed after organization and SSO layers.

---

## Responsibilities

1. **Create SCPs for each OU** (Management, Workloads, Clients)
2. **Attach SCPs to OUs** (not individual accounts)
3. **Define allowed AWS services** per OU
4. **Enforce regional restrictions** (primarily us-east-1)
5. **Reduce attack surface** through service allow-listing

**Design Goal**: Implement defense-in-depth security at the organization level, constraining what all accounts can do regardless of IAM permissions.

---

## SCP Strategy Per OU

### Management OU (Minimal Restrictions)

**Philosophy**: Management account needs broad permissions to govern the organization, but should deny destructive actions.

**Allowed Services**:
- All IAM, STS, IAM Identity Center operations
- AWS Organizations (full access)
- S3, DynamoDB (for state backend)
- Route53 Domains (domain registration only)
- CloudWatch, CloudTrail (monitoring, auditing)

**Denied Actions**:
- Destructive organization actions (delete org, leave org, remove account)
- Root user actions (future: force SSO/IAM roles only)

**Rationale**: Keep management account operational for governance, but prevent accidental organization destruction.

### Workloads OU (Restrictive)

**Philosophy**: Production workload accounts should only access services needed for website infrastructure.

**Allowed Services**:
- IAM, STS (identity management)
- S3, DynamoDB (storage, state backend)
- Route53 (DNS zones only, NOT domains)
- ACM (certificates)
- CloudFront (CDN)
- CloudWatch (monitoring)

**Denied Actions**:
- All other AWS services (EC2, RDS, Lambda, etc. unless explicitly added)
- Operations outside us-east-1 (except global services)
- Root user actions (force IAM roles/SSO)

**Rationale**: Strict service allow-list reduces attack surface and prevents accidental cost overruns.

### Clients OU (Similar to Workloads)

**Philosophy**: Same restrictions as Workloads OU, with potential additional cost controls.

**Allowed Services**: Same as Workloads OU

**Additional Restrictions** (future):
- Instance type restrictions (if compute added)
- Regional restrictions (per-client basis)
- Cost quotas (via tagging policies)

### Sandbox OU (Permissive, Future)

**Philosophy**: Experimentation and learning, no production workloads.

**Allowed Services**: Broader set (add EC2, Lambda, etc. for testing)

**Additional Restrictions**:
- No production data allowed
- Cost alerts at low thresholds
- Automatic resource cleanup (future: nightly Lambda)

---

## Resources Created

### Management OU SCP

```hcl
resource "aws_organizations_policy" "management_ou" {
  name        = "management-ou-scp"
  description = "Minimal restrictions for management account (governance)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAllExceptDestructiveOrgActions"
        Effect = "Allow"
        Action = ["*"]
        Resource = "*"
      },
      {
        Sid    = "DenyDestructiveOrgActions"
        Effect = "Deny"
        Action = [
          "organizations:DeleteOrganization",
          "organizations:LeaveOrganization",
          "organizations:RemoveAccountFromOrganization"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    ManagedBy    = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "management_ou" {
  policy_id = aws_organizations_policy.management_ou.id
  target_id = var.management_ou_id  # From organization layer output
}
```

### Workloads OU SCP

```hcl
resource "aws_organizations_policy" "workloads_ou" {
  name        = "workloads-ou-scp"
  description = "Restrictive SCP for production workload accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRequiredServices"
        Effect = "Allow"
        Action = [
          # Core identity
          "iam:*",
          "sts:*",

          # Storage
          "s3:*",
          "dynamodb:*",

          # DNS & Certificates (zones only, not domains)
          "route53:Get*",
          "route53:List*",
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "acm:*",

          # CDN
          "cloudfront:*",

          # Monitoring
          "cloudwatch:*",
          "logs:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "EnforceRegion"
        Effect = "Deny"
        NotAction = [
          # Global services (no region constraint)
          "iam:*",
          "route53:*",
          "cloudfront:*",
          "sts:*",
          "acm:*",  # ACM for CloudFront must be in us-east-1
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["us-east-1"]
          }
        }
      },
      {
        Sid    = "DenyRootUser"
        Effect = "Deny"
        Action = ["*"]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = ["arn:aws:iam::*:root"]
          }
        }
      }
    ]
  })

  tags = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    ManagedBy    = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "workloads_ou" {
  policy_id = aws_organizations_policy.workloads_ou.id
  target_id = var.workloads_ou_id  # From organization layer output
}
```

### Clients OU SCP (Future)

```hcl
resource "aws_organizations_policy" "clients_ou" {
  name        = "clients-ou-scp"
  description = "Restrictive SCP for client workload accounts"
  type        = "SERVICE_CONTROL_POLICY"

  # Same content as workloads_ou (for now)
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Same as Workloads OU
    ]
  })

  tags = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    ManagedBy    = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "clients_ou" {
  policy_id = aws_organizations_policy.clients_ou.id
  target_id = var.clients_ou_id  # From organization layer output
}
```

---

## Variables

### Required Variables

```hcl
variable "management_ou_id" {
  type        = string
  description = "Management OU ID (from organization layer output)"
}

variable "workloads_ou_id" {
  type        = string
  description = "Workloads OU ID (from organization layer output)"
}

variable "clients_ou_id" {
  type        = string
  description = "Clients OU ID (from organization layer output)"
}
```

### Optional Variables

```hcl
variable "allowed_regions" {
  type        = list(string)
  description = "Allowed AWS regions for workload accounts"
  default     = ["us-east-1"]
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Organization = "noise2signal-llc"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}
```

---

## Outputs

```hcl
output "management_ou_scp_id" {
  value       = aws_organizations_policy.management_ou.id
  description = "Management OU SCP policy ID"
}

output "workloads_ou_scp_id" {
  value       = aws_organizations_policy.workloads_ou.id
  description = "Workloads OU SCP policy ID"
}

output "clients_ou_scp_id" {
  value       = aws_organizations_policy.clients_ou.id
  description = "Clients OU SCP policy ID"
}

output "allowed_services_workloads" {
  value = [
    "iam",
    "sts",
    "s3",
    "dynamodb",
    "route53 (zones only)",
    "acm",
    "cloudfront",
    "cloudwatch",
  ]
  description = "Allowed services in Workloads OU"
}
```

---

## Authentication & Permissions

### Initial Deployment
**Authentication**: Root user, admin IAM user, or SSO admin

**Required Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "organizations:CreatePolicy",
        "organizations:UpdatePolicy",
        "organizations:DeletePolicy",
        "organizations:AttachPolicy",
        "organizations:DetachPolicy",
        "organizations:DescribePolicy",
        "organizations:ListPolicies",
        "organizations:ListTargetsForPolicy"
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
  region = "us-east-1"  # Organizations is global, but use us-east-1
}
```

---

## State Management

### Initial State (Local)
```hcl
# backend.tf (initially commented out)
# terraform {
#   backend "s3" {
#     bucket         = "n2s-terraform-state-management"
#     key            = "management/scp.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-management-lock"
#     encrypt        = true
#   }
# }
```

**After tfstate-backend layer**: Uncomment and migrate to S3

---

## Deployment

### Prerequisites
1. Organization layer deployed (OUs exist)
2. SSO layer deployed (for admin access)
3. OU IDs known (from organization layer outputs)

### Step 1: Get OU IDs from Organization Layer

```bash
cd ../organization
terraform output management_ou_id
terraform output workloads_ou_id
terraform output clients_ou_id
```

### Step 2: Create terraform.tfvars

```hcl
# management/scp/terraform.tfvars
management_ou_id = "ou-xxxx-xxxxxxxx"  # From organization layer
workloads_ou_id  = "ou-xxxx-xxxxxxxx"  # From organization layer
clients_ou_id    = "ou-xxxx-xxxxxxxx"  # From organization layer
```

### Step 3: Initialize Terraform

```bash
cd management/scp
terraform init
```

### Step 4: Review Plan

```bash
terraform plan
```

**Expected Resources**:
- 3 SCP policies (Management, Workloads, Clients)
- 3 policy attachments (one per OU)

### Step 5: Apply

```bash
terraform apply
```

**Timeline**: ~1-2 minutes

### Step 6: Verify

```bash
# List all SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Describe specific SCP
aws organizations describe-policy --policy-id <POLICY_ID>

# List attachments for SCP
aws organizations list-targets-for-policy --policy-id <POLICY_ID>

# Verify OUs have SCPs attached
aws organizations list-policies-for-target --target-id <OU_ID> \
  --filter SERVICE_CONTROL_POLICY
```

---

## Testing SCPs

### Test in Management Account

**Should Succeed** (allowed services):
```bash
# Use SSO to access management account
aws sso login --profile management-admin

# Test allowed services
aws iam list-roles --max-items 5
aws s3 ls
aws organizations describe-organization
```

**Should Fail** (destructive actions):
```bash
# This should be blocked by SCP
aws organizations delete-organization
# Error: Access Denied (SCP denied)
```

### Test in Whollyowned Account

**Should Succeed** (allowed services):
```bash
# Use SSO to access whollyowned account
aws sso login --profile whollyowned-admin

# Test allowed services
aws s3 ls
aws route53 list-hosted-zones
aws cloudfront list-distributions
```

**Should Fail** (blocked services):
```bash
# These should be blocked by SCP
aws ec2 describe-instances
# Error: Access Denied (SCP denied)

aws rds describe-db-instances
# Error: Access Denied (SCP denied)
```

**Should Fail** (root user access, if DenyRootUser is enabled):
```bash
# Log in as root user to whollyowned account
# Any action should fail (except billing/account settings)
```

---

## Post-Deployment Tasks

### 1. Verify SCP Attachments

```bash
# List all SCPs in organization
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Verify each OU has correct SCP
for ou_id in $(terraform output -json | jq -r '.management_ou_id.value, .workloads_ou_id.value, .clients_ou_id.value'); do
  echo "Policies for OU: $ou_id"
  aws organizations list-policies-for-target --target-id $ou_id --filter SERVICE_CONTROL_POLICY
done
```

### 2. Test Service Restrictions

Create a test IAM user in whollyowned account (via management account assume-role):
```bash
# Assume role in whollyowned account
aws sts assume-role \
  --role-arn arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/OrganizationAccountAccessRole \
  --role-session-name test-scp

# Try to launch EC2 instance (should fail)
aws ec2 run-instances --image-id ami-12345678 --instance-type t2.micro
# Expected: Access Denied (SCP)

# Try to use allowed service (should succeed)
aws s3 ls
```

### 3. Proceed to Next Layer

**Next**: Deploy `management/tfstate-backend` layer (optional, migrate state to S3)

---

## Adding New Services

When a new service is needed (e.g., Lambda for website functions):

### Step 1: Update SCP Policy

```hcl
# In main.tf, add to Workloads OU SCP
{
  Sid    = "AllowRequiredServices"
  Effect = "Allow"
  Action = [
    # ... existing services ...
    "lambda:*",  # Added
  ]
  Resource = "*"
}
```

### Step 2: Apply Changes

```bash
terraform plan
terraform apply
```

### Step 3: Test New Service

```bash
# In whollyowned account
aws lambda list-functions
# Should work now
```

---

## Troubleshooting

### Error: Access Denied in Workload Account

**Symptoms**: Terraform operations fail with "Access Denied" despite correct IAM policies

**Cause**: Service not allowed in Workloads OU SCP

**Resolution**:
1. Identify required service from error message
2. Add service to SCP allowed list (Workloads OU)
3. Apply SCP changes
4. Retry infrastructure deployment

**Example**:
```
Error: creating CloudWatch alarm: Access Denied
→ Add "cloudwatch:*" to Workloads OU SCP
```

### Error: Cannot Attach SCP to OU

**Symptoms**: SCP policy created but attachment fails

**Cause**: Invalid OU ID, OU doesn't exist

**Resolution**:
```bash
# Verify OU exists
aws organizations describe-organizational-unit --organizational-unit-id <OU_ID>

# List all OUs
aws organizations list-organizational-units-for-parent --parent-id <ROOT_ID>
```

### Management Account Operations Blocked

**Symptoms**: Cannot perform legitimate governance operations in management account

**Cause**: Management OU SCP too restrictive

**Resolution**:
1. Review Management OU SCP (should be minimal)
2. Ensure governance operations are allowed (IAM, Organizations, etc.)
3. Use root user as fallback (SCPs don't apply to root)

### Cannot Delete SCP

**Symptoms**: `terraform destroy` fails to delete SCP

**Cause**: SCP still attached to OU

**Resolution**:
```bash
# Detach SCP from all OUs first
aws organizations detach-policy --policy-id <POLICY_ID> --target-id <OU_ID>

# Then delete SCP
aws organizations delete-policy --policy-id <POLICY_ID>
```

---

## Security Considerations

### Defense in Depth

**SCPs are the first line of defense**:
1. SCPs (organization-level) → Constrain all accounts
2. IAM policies (account-level) → Constrain users/roles
3. Resource policies (resource-level) → Constrain resource access

**Even if IAM policies are misconfigured**, SCPs prevent unauthorized service usage.

### Least Privilege

- **Management OU**: Minimal restrictions (governance requires broad access)
- **Workloads OU**: Strict service allow-list (only what's needed for websites)
- **Clients OU**: Same as Workloads (future: per-client customization)

### SCP Limitations

**SCPs do NOT apply to**:
- Management account root user (use sparingly!)
- Service-linked roles (AWS-created roles for service integration)

**SCPs CANNOT**:
- Grant permissions (only deny/restrict)
- Override explicit denies in IAM policies

### Testing Strategy

**Always test SCPs before applying to production OUs**:
1. Create test OU
2. Move test account to test OU
3. Apply SCP to test OU
4. Verify operations work as expected
5. Move SCP to production OU

---

## Maintenance

### Regular Reviews

**Quarterly**:
- Review SCP policies for unnecessary permissions
- Remove services that are no longer used
- Update regional restrictions if multi-region expansion needed

**After Major Changes**:
- New service added to infrastructure → Update SCP
- Account moved between OUs → Verify SCP still appropriate
- New compliance requirements → Update SCP to enforce

### Monitoring

**CloudTrail Integration** (future):
- Monitor SCP-denied actions (indicates potential misconfigurations)
- Alert on repeated Access Denied errors (may indicate SCP too restrictive)

---

## Cost Considerations

**Service Control Policies**: Free (no AWS charges for SCPs)

**Indirect Cost Savings**:
- Prevents accidental resource creation in expensive services
- Enforces regional restrictions (avoids data transfer costs)

---

## References

### Related Layers
- [../CLAUDE.md](../CLAUDE.md) - Management account overview
- [../organization/CLAUDE.md](../organization/CLAUDE.md) - Organization layer (OUs)
- [../sso/CLAUDE.md](../sso/CLAUDE.md) - SSO layer (authentication)

### AWS Documentation
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [SCP Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_strategies.html)
- [Testing SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)

---

**Layer**: 2 (SCP)
**Account**: noise2signal-llc-management
**Last Updated**: 2026-01-26
