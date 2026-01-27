# SCP Layer - Service Control Policies

## Purpose

The **SCP layer** defines **Service Control Policies** that constrain AWS accounts in the organization to only explicitly allowed services. SCPs act as organizational guardrails, preventing accidental usage of unintended AWS services.

**Layer 2** - Deployed after organization and SSO layers

**Design Goal:** Implement intentional infrastructure engineering through service allow-listing. Even with full admin access via SSO, SCPs require deliberate enablement of new services.

---

## Why SCPs for Single-User Use Case

While SCPs are often associated with multi-user organizations, they provide significant value even for a single operator:

### Cost Control
- **Prevent accidental expensive services:** Cannot accidentally spin up EC2 fleet, RDS clusters, or other compute resources
- **Regional restrictions:** Limits spend to intended regions (primarily us-east-1 for static sites)
- **Predictable billing:** Only services explicitly enabled can incur charges

### Intentional Engineering
- **Forced deliberation:** To use a new service, must first update SCP via Terraform
- **Infrastructure as Code discipline:** Service enablement becomes a documented, version-controlled decision
- **Prevents console experimentation:** Cannot enable services on a whim in AWS Console

### Professional Demonstration
- **Governance best practices:** Demonstrates understanding of AWS Organizations and defense-in-depth security
- **Production-ready architecture:** Shows ability to design proper multi-account structures
- **Portfolio value:** Illustrates professional engineering discipline

### Self-Imposed Guardrails
- **Protection from yourself:** Limits mistakes even with full admin access
- **Clear intentions:** SCP explicitly documents which services are in use
- **Audit trail:** Changes to SCPs create clear history of when services were enabled

---

## Current Scope

### Organizational Units to Manage

**Management OU: "Noise2Signal LLC Management"**
- Purpose: AWS governance and billing
- SCP: Minimal restrictions (allow governance operations, deny destructive actions)

**Proprietary Workloads OU**
- Purpose: Production websites and static site infrastructure
- SCP: Restrictive service allow-list (only services needed for static sites)

### Future OUs (Deferred)

Client OUs and additional organizational units deferred to FUTURE_CONCERNS.md.

---

## SCP Strategy Per OU

### Management OU SCP (Minimal Restrictions)

**Philosophy:** Management account needs broad permissions for governance, but prevent destructive actions.

**Allowed Services:**
- All IAM, STS, IAM Identity Center operations
- AWS Organizations (full access)
- S3, DynamoDB (for state backend, future)
- Route53 Domains (domain registration operations only)
- CloudWatch, CloudTrail (monitoring, auditing)

**Denied Actions:**
- Destructive organization operations (delete org, leave org, remove account)

**Rationale:** Keep management account operational for governance while preventing accidental organization destruction.

### Proprietary Workloads OU SCP (Restrictive)

**Philosophy:** Workload accounts should only access services needed for static website infrastructure. All other services explicitly denied.

**Allowed Services:**
- **Identity:** IAM, STS (for role management and temporary credentials)
- **Storage:** S3 (static site content)
- **DNS:** Route53 (hosted zones and record sets only, NOT domain registration)
- **Certificates:** ACM (TLS certificates for CloudFront)
- **CDN:** CloudFront (content delivery)
- **Monitoring:** CloudWatch, CloudWatch Logs (metrics and logging)

**Denied:**
- All compute services (EC2, Lambda, ECS, EKS, etc.)
- All database services (RDS, DynamoDB, Aurora, etc.)
- All other AWS services not explicitly listed
- Operations outside us-east-1 region (except global services)

**Rationale:**
- **Cost control:** Prevents accidental EC2/RDS launches
- **Reduced attack surface:** Limits what compromised credentials could do
- **Clear intentions:** Explicitly documents that this account is for static sites only

---

## Resources to Create

### Management OU SCP

```hcl
resource "aws_organizations_policy" "management_ou" {
  name        = "management-ou-scp"
  description = "Minimal restrictions for management OU (governance operations)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAllServices"
        Effect   = "Allow"
        Action   = ["*"]
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
    Organization = "Noise2Signal LLC"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "scp"
  }
}

resource "aws_organizations_policy_attachment" "management_ou" {
  policy_id = aws_organizations_policy.management_ou.id
  target_id = var.management_ou_id  # From organization layer output
}
```

### Proprietary Workloads OU SCP

```hcl
resource "aws_organizations_policy" "proprietary_workloads_ou" {
  name        = "proprietary-workloads-ou-scp"
  description = "Restrictive SCP for proprietary workload accounts (static sites only)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStaticSiteServices"
        Effect = "Allow"
        Action = [
          # Identity management
          "iam:*",
          "sts:*",

          # Storage
          "s3:*",

          # DNS (zones only, not domains)
          "route53:Get*",
          "route53:List*",
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:UpdateHostedZone*",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:CreateHealthCheck",
          "route53:DeleteHealthCheck",
          "route53:UpdateHealthCheck",

          # Certificates
          "acm:*",

          # CDN
          "cloudfront:*",

          # Monitoring
          "cloudwatch:*",
          "logs:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EnforceUsEast1"
        Effect = "Deny"
        NotAction = [
          # Global services (no region constraint)
          "iam:*",
          "route53:*",
          "cloudfront:*",
          "sts:*",
          "acm:*"  # ACM for CloudFront must be in us-east-1
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

  tags = {
    Organization = "Noise2Signal LLC"
    Account      = "management"
    CostCenter   = "infrastructure"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "scp"
  }
}

resource "aws_organizations_policy_attachment" "proprietary_workloads_ou" {
  policy_id = aws_organizations_policy.proprietary_workloads_ou.id
  target_id = var.proprietary_workloads_ou_id  # From organization layer output
}
```

**Key Design Decisions:**

**No root user denial:** Root user denial removed to avoid lockout scenarios. Root user should still be used only for break-glass.

**Service allow-list:** Only services explicitly needed for static sites. To add new services (e.g., Lambda@Edge), must update SCP first.

**Regional enforcement:** us-east-1 only (except global services). CloudFront and ACM are global/us-east-1 respectively.

---

## Variables

### Required Variables

```hcl
variable "management_ou_id" {
  type        = string
  description = "Management OU ID (from organization layer output)"
}

variable "proprietary_workloads_ou_id" {
  type        = string
  description = "Proprietary Workloads OU ID (from organization layer output)"
}
```

### Optional Variables

```hcl
variable "allowed_regions" {
  type        = list(string)
  description = "Allowed AWS regions for workload accounts"
  default     = ["us-east-1"]
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
    Layer        = "scp"
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

output "management_ou_scp_arn" {
  value       = aws_organizations_policy.management_ou.arn
  description = "Management OU SCP policy ARN"
}

output "proprietary_workloads_ou_scp_id" {
  value       = aws_organizations_policy.proprietary_workloads_ou.id
  description = "Proprietary Workloads OU SCP policy ID"
}

output "proprietary_workloads_ou_scp_arn" {
  value       = aws_organizations_policy.proprietary_workloads_ou.arn
  description = "Proprietary Workloads OU SCP policy ARN"
}

output "allowed_services_proprietary_workloads" {
  value = [
    "iam",
    "sts",
    "s3",
    "route53 (zones only)",
    "acm",
    "cloudfront",
    "cloudwatch"
  ]
  description = "Allowed services in Proprietary Workloads OU"
}
```

---

## Deployment

### Prerequisites

1. **Organization layer deployed** (OUs exist)
2. **SSO layer deployed** (for admin access)
3. **OU IDs known** (from organization layer outputs)
4. **Proprietary Signals account created** (optional, but SCP will apply when created)

### Step 1: Get OU IDs from Organization Layer

```bash
cd organization/
terraform output management_ou_id
terraform output proprietary_workloads_ou_id
```

### Step 2: Create terraform.tfvars

```hcl
# scp/terraform.tfvars
management_ou_id              = "ou-xxxx-xxxxxxxx"  # From organization layer
proprietary_workloads_ou_id   = "ou-xxxx-xxxxxxxx"  # From organization layer
```

**Important:** Add `*.tfvars` to `.gitignore`

### Step 3: Initialize Terraform

```bash
cd scp/
terraform init
```

### Step 4: Review Plan

```bash
terraform plan
```

**Expected resources:**
- 2 SCP policies (Management OU, Proprietary Workloads OU)
- 2 policy attachments (one per OU)

**Timeline:** 1-2 minutes

### Step 5: Apply

```bash
terraform apply
```

### Step 6: Verify

```bash
# List all SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# Describe Management OU SCP
aws organizations describe-policy --policy-id $(terraform output -raw management_ou_scp_id)

# Describe Proprietary Workloads OU SCP
aws organizations describe-policy --policy-id $(terraform output -raw proprietary_workloads_ou_scp_id)

# List policies attached to Management OU
aws organizations list-policies-for-target \
  --target-id $(terraform output -raw management_ou_id) \
  --filter SERVICE_CONTROL_POLICY

# List policies attached to Proprietary Workloads OU
aws organizations list-policies-for-target \
  --target-id $(terraform output -raw proprietary_workloads_ou_id) \
  --filter SERVICE_CONTROL_POLICY
```

---

## Testing SCPs

### Test Management OU SCP

**Test allowed services:**

```bash
# Login via SSO to management account
aws sso login --profile management-sso

# Should succeed (governance operations allowed)
aws organizations describe-organization
aws iam list-roles --max-items 5
aws s3 ls
```

**Test denied destructive actions:**

```bash
# Should fail with Access Denied (SCP blocks this)
aws organizations delete-organization
# Expected error: User: <user> is not authorized to perform: organizations:DeleteOrganization because of a service control policy
```

### Test Proprietary Workloads OU SCP

**Prerequisites:**
- Proprietary Signals account created
- SSO access configured to Proprietary Signals account

**Test allowed services:**

```bash
# Login via SSO to Proprietary Signals account
aws sso login --profile proprietary-signals-sso

# Should succeed (static site services allowed)
aws s3 ls
aws route53 list-hosted-zones
aws cloudfront list-distributions
aws acm list-certificates --region us-east-1
```

**Test denied services (cost control in action):**

```bash
# Should fail - EC2 not allowed
aws ec2 describe-instances
# Expected error: User: <user> is not authorized to perform: ec2:DescribeInstances because of a service control policy

# Should fail - Lambda not allowed
aws lambda list-functions
# Expected error: User: <user> is not authorized to perform: lambda:ListFunctions because of a service control policy

# Should fail - RDS not allowed
aws rds describe-db-instances
# Expected error: User: <user> is not authorized to perform: rds:DescribeDBInstances because of a service control policy

# Should fail - DynamoDB not allowed (not needed for static sites)
aws dynamodb list-tables
# Expected error: User: <user> is not authorized to perform: dynamodb:ListTables because of a service control policy
```

**Test regional restrictions:**

```bash
# Should fail - us-west-2 not allowed
aws s3 ls --region us-west-2
# Expected error: Service control policy prevents this action in this region
```

**Result:** Even with AdministratorAccess permission set via SSO, you cannot use services not explicitly allowed in the SCP. To enable a new service, must update SCP first.

---

## Post-Deployment Tasks

### 1. Verify SCP Attachments

```bash
# Verify Management OU has SCP
aws organizations list-policies-for-target \
  --target-id $(cd ../organization && terraform output -raw management_ou_id) \
  --filter SERVICE_CONTROL_POLICY

# Verify Proprietary Workloads OU has SCP
aws organizations list-policies-for-target \
  --target-id $(cd ../organization && terraform output -raw proprietary_workloads_ou_id) \
  --filter SERVICE_CONTROL_POLICY
```

### 2. Document Allowed Services

Create a quick reference document for which services are enabled:

```bash
# Output allowed services
terraform output allowed_services_proprietary_workloads
```

### 3. Backup State File

```bash
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
```

### 4. Commit Code

```bash
git add *.tf
git commit -m "Add SCPs for Management and Proprietary Workloads OUs"
git push origin main
```

---

## Adding New Services to Proprietary Workloads OU

When you need a new service (e.g., Lambda@Edge for CloudFront functions):

### Step 1: Identify Required Service Actions

Determine exact AWS service actions needed:
- Check AWS documentation
- Review Terraform provider documentation
- Note required permissions

### Step 2: Update SCP Policy

Edit `main.tf`:

```hcl
resource "aws_organizations_policy" "proprietary_workloads_ou" {
  # ... existing code ...

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStaticSiteServices"
        Effect = "Allow"
        Action = [
          # ... existing services ...

          # Lambda@Edge (newly added)
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:GetFunctionConfiguration",
          "lambda:ListVersionsByFunction"
        ]
        Resource = "*"
      },
      # ... rest of policy ...
    ]
  })
}
```

### Step 3: Plan and Apply

```bash
terraform plan
# Review changes - should show SCP policy update

terraform apply
```

### Step 4: Test New Service

```bash
# Login to Proprietary Signals account
aws sso login --profile proprietary-signals-sso

# Test new service (should now work)
aws lambda list-functions
```

### Step 5: Document Change

Update this CLAUDE.md file's "Allowed Services" section to reflect new service.

---

## Troubleshooting

### Error: Access Denied Despite IAM Permissions

**Symptoms:** Operations fail with "Access Denied" even though IAM permissions are correct.

**Cause:** Service not allowed in OU's SCP.

**Resolution:**
1. Check which OU the account is in
2. Review SCP for that OU
3. Add required service to SCP
4. Apply SCP changes
5. Retry operation

**Example:**
```
Error: creating Lambda function: AccessDenied
→ Check if Lambda is in Proprietary Workloads OU SCP
→ If not, add "lambda:*" to AllowStaticSiteServices statement
→ Apply SCP changes
```

### Error: Cannot Attach SCP to OU

**Symptoms:** `terraform apply` fails when attaching SCP to OU.

**Cause:** Invalid OU ID or OU doesn't exist.

**Resolution:**
```bash
# Verify OU exists
aws organizations describe-organizational-unit \
  --organizational-unit-id <ou-id>

# List all OUs under root
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID
```

### Management Account Operations Blocked

**Symptoms:** Cannot perform governance operations in management account.

**Cause:** Management OU SCP too restrictive.

**Resolution:**
- Verify Management OU SCP allows broad permissions
- Use root user as fallback (SCPs don't apply to root user)
- Update SCP to allow required governance operations

### Locked Out of Account

**Symptoms:** No operations work in an account after applying SCP.

**Cause:** SCP is too restrictive or blocks all actions.

**Immediate Resolution:**
1. **Use root user:** SCPs don't apply to root user
2. Login as root user to affected account
3. Verify SCP via management account
4. Fix SCP policy via management account

**Prevention:**
- Always test SCPs in non-critical accounts first
- Keep Management OU SCP minimal
- Never deny "sts:AssumeRole" (breaks cross-account access)

### Cannot Delete SCP

**Symptoms:** `terraform destroy` fails to delete SCP.

**Cause:** SCP still attached to OU.

**Resolution:**
```bash
# Detach SCP from OU first
aws organizations detach-policy \
  --policy-id <policy-id> \
  --target-id <ou-id>

# Then delete SCP
aws organizations delete-policy --policy-id <policy-id>
```

---

## Security Considerations

### Defense in Depth

SCPs are the **outer layer** of security:

1. **SCP (Organization):** Defines maximum possible permissions
2. **IAM Policies (Account):** Grant permissions within SCP limits
3. **Resource Policies (Resource):** Further restrict access to specific resources

Even if IAM policies grant broad permissions, SCPs limit what's actually possible.

### SCP Limitations

**SCPs do NOT apply to:**
- **Root user:** Management account root user can bypass all SCPs
- **Service-linked roles:** AWS-created roles for service integration

**SCPs CANNOT:**
- **Grant permissions:** Only restrict/deny actions (allow-list approach)
- **Override IAM denies:** IAM explicit denies always win

### Best Practices

1. **Start restrictive, expand as needed:** Easier to add services than remove
2. **Document all changes:** Why was each service added to SCP?
3. **Version control:** All SCP changes via Terraform
4. **Test before production:** Verify SCP doesn't break existing operations
5. **Regular audits:** Quarterly review of allowed services (remove unused)

### Root User Access

**Root user bypasses SCPs** - use only for:
- Break-glass access when SCPs lock you out
- Billing/payment method changes
- Closing accounts
- Enabling/disabling AWS regions

**Never use root user for:**
- Daily operations (use SSO)
- Infrastructure deployment (use SSO + Terraform)
- Testing (use SSO with AdministratorAccess)

---

## Cost Impact

### Direct Costs

**Service Control Policies:** Free (no AWS charges)

### Indirect Cost Savings

**Prevent accidental expensive services:**
- Cannot launch EC2 instances → Saves $50-500/month per instance
- Cannot create RDS databases → Saves $100-1000/month per database
- Cannot enable Compute/Database services → Prevents runaway costs

**Regional restrictions:**
- Prevents multi-region data transfer charges
- Limits spend to intended regions

**Estimated cost prevention:** $100-5000/month (prevents accidental launches)

---

## Next Steps

### After Completing SCP Layer

1. **Verify cost control:**
   - Test that expensive services are blocked
   - Verify you cannot launch EC2, RDS, etc.
   - Confirm static site services still work

2. **Set up workload repository:**
   - Create `iac-aws-proprietary` repository
   - Deploy static site infrastructure
   - Verify SCP doesn't block deployment

3. **Monitor for SCP denials:**
   - Check CloudTrail for "AccessDenied" errors
   - If legitimate operations are blocked, update SCP
   - If suspicious operations are blocked, investigate

4. **Document enabled services:**
   - Keep list of which services are in SCP
   - Update documentation when services added
   - Regular quarterly reviews

---

## References

### Documentation
- [Main Architecture](../CLAUDE.md) - Overall AWS organization architecture
- [Organization Layer](../organization/CLAUDE.md) - OU structure
- [SSO Layer](../sso/CLAUDE.md) - Authentication layer
- [Future Concerns](../FUTURE_CONCERNS.md) - Deferred features

### AWS Documentation
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [SCP Syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_syntax.html)
- [SCP Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_strategies.html)
- [Testing SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)

### Terraform Documentation
- [aws_organizations_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy)
- [aws_organizations_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment)

---

**Layer:** 2 (SCP)
**Account:** Noise2Signal LLC (Management)
**Status:** Ready to deploy
**Last Updated:** 2026-01-27
