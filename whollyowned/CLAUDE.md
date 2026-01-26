# Whollyowned Account - Overview

## Purpose

The **whollyowned account** (`noise2signal-llc-whollyowned`) is a production workload account for Noise2Signal LLC's branded websites. It hosts all infrastructure for wholly-owned properties (websites, CDN, DNS, certificates) - assets where N2S retains full intellectual property rights.

**Primary Responsibilities**:
- Route53 hosted zones (public DNS for N2S domains)
- ACM certificates (SSL/TLS for HTTPS)
- S3 buckets (website content storage)
- CloudFront distributions (global CDN)
- IAM roles (Terraform execution, CI/CD authentication)

**Design Principle**: Isolate production workloads from management/governance infrastructure. All website assets live here, not in the management account.

---

## Account Details

**Account Name**: `noise2signal-llc-whollyowned`
**Account Email**: `aws-whollyowned@noise2signal.com` (or similar)
**Account ID**: Set during organization layer deployment
**Organizational Unit**: `Workloads/Production`
**Cost Center Tag**: `whollyowned`

**Created By**: Management account (organization layer)
**Access Method**: AWS SSO (IAM Identity Center) from management account

---

## Layer Structure

The whollyowned account has four layers, deployed in sequence:

```
whollyowned/
├── CLAUDE.md                       # This file
├── rbac/                           # Layer 0: IAM Roles + OIDC
│   ├── CLAUDE.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── backend.tf (commented initially)
│
├── tfstate-backend/                # Layer 1: Terraform State Backend
│   ├── CLAUDE.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── backend.tf (commented initially)
│
├── domains/                        # Layer 2: Route53 Zones + ACM
│   ├── CLAUDE.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── backend.tf (commented initially)
│   └── terraform.tfvars (gitignored)
│
└── sites/                          # Layer 3: S3 + CloudFront + DNS
    ├── CLAUDE.md
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── provider.tf
    ├── backend.tf (commented initially)
    └── terraform.tfvars (gitignored)
```

---

## Deployment Sequence

### Prerequisites

- Management account deployed (organization, SSO, SCPs)
- Whollyowned account created (by organization layer)
- SSO access configured (boss user can access whollyowned account)
- AWS CLI configured with whollyowned SSO profile

### Layer 0: RBAC

**Purpose**: Create IAM roles for Terraform execution and GitHub OIDC provider

**Authentication**: SSO admin (via management account SSO)
**State**: Local (initially)

**Key Actions**:
- Create GitHub OIDC provider (federated authentication)
- Create IAM roles:
  - `tfstate-terraform-role` (state backend management)
  - `domains-terraform-role` (Route53 + ACM management)
  - `sites-terraform-role` (S3 + CloudFront + DNS management)
- Configure trust policies (trust GitHub OIDC provider)
- Attach least-privilege IAM policies per role

**Outputs**: IAM role ARNs, OIDC provider ARN

**See**: [rbac/CLAUDE.md](./rbac/CLAUDE.md)

### Layer 1: Tfstate Backend

**Purpose**: Create S3 bucket and DynamoDB table for whollyowned state storage

**Authentication**: Assumes `tfstate-terraform-role` (via SSO or GitHub Actions)
**State**: Local → Remote (migrates after creation)

**Key Actions**:
- Create S3 bucket (`n2s-terraform-state-whollyowned`)
- Enable versioning, encryption, lifecycle policies
- Create DynamoDB table for state locking
- Migrate all whollyowned layers to remote state

**Outputs**: Bucket name, DynamoDB table name

**See**: [tfstate-backend/CLAUDE.md](./tfstate-backend/CLAUDE.md)

### Layer 2: Domains

**Purpose**: Create Route53 hosted zones and ACM certificates

**Authentication**: Assumes `domains-terraform-role`
**State**: Remote (after tfstate-backend migration) or Local (initially)

**Key Actions**:
- Create Route53 hosted zones (public DNS)
- Create ACM certificates (DNS validation, us-east-1 for CloudFront)
- Output nameservers for manual update in management account

**Outputs**: Hosted zone IDs, ACM certificate ARNs, nameservers

**Cross-Account Dependency**: NS records must be manually updated in management account domain registrations (Phase 3 of bootstrap)

**See**: [domains/CLAUDE.md](./domains/CLAUDE.md)

### Layer 3: Sites

**Purpose**: Deploy website infrastructure (S3, CloudFront, DNS records)

**Authentication**: Assumes `sites-terraform-role`
**State**: Remote (after tfstate-backend migration) or Local (initially)

**Key Actions**:
- Create S3 buckets (primary + www redirect)
- Create CloudFront distributions (CDN)
- Create Route53 A/AAAA records (point to CloudFront)
- Configure Origin Access Control (OAC) for S3

**Outputs**: S3 bucket names, CloudFront distribution IDs, website URLs

**See**: [sites/CLAUDE.md](./sites/CLAUDE.md)

---

## Service Control Policies (Applied to This Account)

The whollyowned account lives in the **Workloads/Production OU**, which has **restrictive SCPs**:

**Allowed Services**:
- IAM, STS (identity management)
- S3, DynamoDB (storage, state backend)
- Route53 (hosted zones only, NOT domain registrations)
- ACM (certificates)
- CloudFront (CDN)
- CloudWatch, CloudTrail (monitoring, auditing)

**Denied Services**:
- All other AWS services (EC2, RDS, Lambda, etc.) - must be explicitly added to SCP
- Operations outside us-east-1 (except global services like CloudFront, IAM)
- Root user actions (force IAM roles/SSO)

**Denied Actions**:
- Route53 domain registration operations (only management account can register domains)

**Rationale**: Strict service allow-list reduces attack surface, prevents accidental cost overruns, and enforces architectural boundaries.

**SCP Source**: Management account SCP layer (`management/scp/`)

---

## IAM Roles

### Terraform Execution Roles

All Terraform operations in the whollyowned account use dedicated IAM roles (created by RBAC layer):

| Role Name | Purpose | Permissions | Trusted By |
|-----------|---------|-------------|------------|
| `tfstate-terraform-role` | State backend management | S3 (bucket CRUD), DynamoDB (table CRUD) | GitHub OIDC |
| `domains-terraform-role` | DNS + certificates | Route53 (zones, records), ACM (certificates) | GitHub OIDC |
| `sites-terraform-role` | Website infrastructure | S3 (buckets), CloudFront (distributions), Route53 (records) | GitHub OIDC |

**All roles also have**: S3 + DynamoDB read/write for state backend access

### GitHub OIDC Provider

Created in RBAC layer, enables GitHub Actions to assume IAM roles without long-lived credentials:

```hcl
# Trust policy for all Terraform roles
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:noise2signal/iac-aws:*"
    }
  }
}
```

**Session Duration**: 1 hour (short-lived tokens)

### Human Access

**Use AWS SSO exclusively** (no IAM users):
- Boss SSO user → AdministratorAccess permission set (configured in management account)
- Future team members → PowerUserAccess or ReadOnlyAccess

**Access Method**:
```bash
aws sso login --profile whollyowned-admin
aws sts get-caller-identity --profile whollyowned-admin
```

---

## Terraform State

### Initial State (Local)

All layers start with local state files:

```
whollyowned/
├── rbac/terraform.tfstate
├── tfstate-backend/terraform.tfstate
├── domains/terraform.tfstate
└── sites/terraform.tfstate
```

**Important**: Add `*.tfstate` to `.gitignore` - never commit state files!

### Remote State (After Layer 1)

After deploying `tfstate-backend` layer, migrate all layers to S3:

```
s3://n2s-terraform-state-whollyowned/
└── whollyowned/
    ├── rbac.tfstate
    ├── tfstate-backend.tfstate
    ├── domains.tfstate
    └── sites.tfstate
```

**State Bucket**: `n2s-terraform-state-whollyowned` (separate from management account)
**Locking Table**: `n2s-terraform-state-whollyowned-lock`

**Migration Steps**:
1. Deploy `tfstate-backend` layer (creates S3 + DynamoDB)
2. Uncomment `backend.tf` in each layer
3. Run `terraform init -migrate-state` in each layer
4. Verify state in S3: `aws s3 ls s3://n2s-terraform-state-whollyowned/whollyowned/`
5. Delete local state files: `rm terraform.tfstate*`

---

## Cost Allocation

All resources in the whollyowned account use these tags:

```hcl
tags = {
  Organization = "noise2signal-llc"
  Account      = "whollyowned"
  CostCenter   = "whollyowned"
  Environment  = "production"
  ManagedBy    = "terraform"
  Layer        = "domains"  # or "sites", "rbac", "tfstate-backend"
}
```

**Cost Center**: `whollyowned` (N2S brand website costs)

**Monthly Cost Estimate (per site)**:
```
IAM roles:                   Free
GitHub OIDC provider:        Free
S3 state backend:            ~$0.10
DynamoDB state locking:      ~$0.25
Route53 hosted zone:         ~$0.50/month
Route53 queries:             ~$0.40 per 1M queries
ACM certificate:             Free (when used with CloudFront)
S3 website storage:          ~$0.023/GB (~$0.02-0.05/month for small site)
S3 requests:                 ~$0.005 per 1K PUT, ~$0.0004 per 1K GET
CloudFront data transfer:    ~$0.085/GB (PriceClass_100: US/CA/EU)
CloudFront requests:         ~$0.0075 per 10K HTTPS requests
──────────────────────────────
Total per site:              ~$1.87-5.87/month (traffic-dependent)
```

**Example (1 site, 10 GB/month traffic)**:
- State backend: $0.35
- Route53: $0.90
- S3: $0.25
- CloudFront: $1.00 (data) + $0.08 (requests) = $1.08
- **Total**: ~$2.58/month

**Scaling**: Each additional site adds ~$1.87-5.87/month

---

## Cross-Account Dependencies

### Management Account → Whollyowned

**Domain Registrations → Hosted Zones**:
- Domain registrations live in **management account** (Route53 Domains)
- Hosted zones live in **whollyowned account** (Route53 hosted zones)
- **Manual step required**: Update domain nameservers in management account with NS records from whollyowned account

**Resolution**:

```bash
# In whollyowned account: Get NS records from hosted zone
aws route53 list-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value" \
  --profile whollyowned-admin

# In management account: Update domain nameservers
aws route53domains update-domain-nameservers \
  --region us-east-1 \
  --domain-name camdenwander.com \
  --nameservers Name=ns-123.awsdns-12.com Name=ns-456.awsdns-45.net ... \
  --profile management-admin
```

**Future Enhancement**: Automate with Terraform data sources or Lambda function

**SSO Access**:
- IAM Identity Center lives in **management account**
- Permission set assignments grant access to **whollyowned account**
- Boss user logs into SSO portal (management account) and selects whollyowned account

### Within Whollyowned Account

**Domains Layer → Sites Layer**:
- Sites layer discovers ACM certificates and Route53 hosted zones via AWS data sources
- No Terraform remote state dependencies (simpler, more reliable)

```hcl
# In sites layer
data "aws_route53_zone" "site" {
  name = var.domain_name
}

data "aws_acm_certificate" "site" {
  provider    = aws.us_east_1
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
```

---

## Security Best Practices

### Service Control Policies

- **Enforced by management account** at Workloads OU level
- **Restricts services** to only what's needed (S3, Route53, CloudFront, etc.)
- **Prevents root user access** (force IAM roles/SSO)
- **Regional restrictions** (us-east-1 for regional services)

### IAM Roles (Least Privilege)

- **One role per layer** (domains, sites, tfstate)
- **Scoped permissions**: Each role can only manage its layer's resources
- **No cross-layer access**: Sites role cannot modify domains, etc.
- **Session duration**: 1 hour (short-lived tokens from GitHub OIDC)

### Encryption

**At Rest**:
- S3 buckets: AES256 server-side encryption (all buckets)
- Terraform state: Encrypted in S3
- DynamoDB: AWS-managed keys

**In Transit**:
- HTTPS enforced: CloudFront redirects HTTP → HTTPS
- TLS 1.2+ minimum protocol
- ACM certificates (automatic renewal)

### Access Control

- **S3 buckets**: CloudFront Origin Access Control (OAC), not public
- **IAM roles**: Trust GitHub OIDC provider only (no long-lived credentials)
- **State backend**: Restricted to Terraform execution roles

### Security Headers (CloudFront)

```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
```

### Domain Security

- **CAA records**: Restrict certificate issuance to AWS only
- **DNSSEC**: Optional (can be enabled for enhanced security)
- **Domain registration lock**: Enabled in management account (prevents unauthorized transfers)

---

## Deployment Workflow

### Initial Bootstrap Commands

**Phase 1: Access Whollyowned Account**

```bash
# Configure SSO profile for whollyowned account
aws configure sso
# SSO start URL: https://d-xxxxxxxxxx.awsapps.com/start (from management account)
# Account: Select whollyowned account
# Role: AdministratorAccess
# Profile name: whollyowned-admin

# Log in
aws sso login --profile whollyowned-admin

# Verify access
aws sts get-caller-identity --profile whollyowned-admin
```

**Phase 2: Deploy RBAC Layer**

```bash
cd whollyowned/rbac
terraform init
terraform apply
# Note IAM role ARNs from outputs
```

**Phase 3: Deploy Tfstate Backend (Optional, Last)**

```bash
cd whollyowned/tfstate-backend
terraform init
terraform apply
# Migrate all whollyowned layers to remote state (see Layer 1 documentation)
```

**Phase 4: Deploy Domains Layer**

```bash
cd whollyowned/domains
# Create terraform.tfvars with domain map
terraform init
terraform apply
# Wait for ACM certificate validation (5-10 minutes)
# Note nameservers from outputs
```

**Phase 5: Update Domain Nameservers (Cross-Account)**

```bash
# Get NS records from whollyowned hosted zone
cd whollyowned/domains
terraform output nameservers_camdenwander_com
# Copy nameserver values

# Switch to management account
aws sso login --profile management-admin

# Update domain registration (see management/domain-registrations layer)
# Manual step via AWS console or CLI
```

**Phase 6: Deploy Sites Layer**

```bash
cd whollyowned/sites
# Create terraform.tfvars with site map
terraform init
terraform apply
# Wait for CloudFront deployment (15-30 minutes)
```

**Phase 7: Upload Website Content**

```bash
# Sync website content to S3
aws s3 sync ./website/ s3://camdenwander.com/ --delete --profile whollyowned-admin

# Invalidate CloudFront cache
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id_camdenwander_com)
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*" \
  --profile whollyowned-admin
```

---

## Adding a New Site

**Prerequisites**:
- Domain transferred to Route53 or ready for registration in management account
- Nameservers updated in management account (Phase 5 complete)

**Process**:

1. **Register domain in management account** (if not already registered)
2. **Add to domains layer in whollyowned account**:
   ```hcl
   # whollyowned/domains/terraform.tfvars
   domains = {
     "camdenwander.com" = { ... },
     "newdomain.com" = { ... },  # Added
   }
   ```
   Apply changes, wait for certificate validation.

3. **Update nameservers in management account** (Phase 5 for new domain)

4. **Add to sites layer in whollyowned account**:
   ```hcl
   # whollyowned/sites/terraform.tfvars
   sites = {
     "camdenwander.com" = { ... },
     "newdomain.com" = { ... },  # Added
   }
   ```
   Apply changes, wait for CloudFront deployment.

5. **Upload content**:
   ```bash
   aws s3 sync ./new-site/ s3://newdomain.com/ --profile whollyowned-admin
   ```

**Timeline**: ~45 minutes (certificate validation + CloudFront deployment)

---

## Troubleshooting

### Cannot Access Whollyowned Account

**Cause**: SSO not configured, permission set not assigned

**Resolution**:
1. Verify SSO configuration in management account
2. Check permission set assignment for boss user → whollyowned account
3. Ensure AdministratorAccess permission set exists
4. Retry SSO login: `aws sso login --profile whollyowned-admin`

### ACM Certificate Validation Stuck

**Cause**: NS records not updated in management account, DNS propagation delay

**Resolution**:
1. Verify nameservers from whollyowned hosted zone match management account domain registration
2. Check DNS propagation: `dig NS camdenwander.com` or `nslookup -type=NS camdenwander.com`
3. Wait for DNS propagation (can take up to 48 hours, usually 5-10 minutes)
4. Re-run `terraform apply` in domains layer

### CloudFront 403 Errors

**Cause**: S3 bucket policy doesn't allow CloudFront OAC access

**Resolution**:
1. Verify S3 bucket policy includes CloudFront OAC principal
2. Check CloudFront distribution has OAC configured
3. Verify S3 bucket is not public (should use OAC, not public access)
4. Re-apply sites layer: `terraform apply`

### Terraform State Locking Timeout

**Cause**: Previous Terraform run failed without releasing lock

**Resolution**:
```bash
# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
# Lock ID shown in error message or in DynamoDB table
```

### Role Assumption Failure (GitHub Actions)

**Cause**: OIDC provider not created, trust policy misconfigured, repository mismatch

**Resolution**:
1. Verify RBAC layer deployed successfully
2. Check OIDC provider exists: `aws iam list-open-id-connect-providers --profile whollyowned-admin`
3. Verify trust policy allows `repo:noise2signal/iac-aws:*`
4. Check GitHub Actions workflow uses correct role ARN

---

## CI/CD (GitHub Actions)

**Workflow Example** (per layer):

```yaml
# .github/workflows/whollyowned-sites.yml
name: Whollyowned - Sites Layer

on:
  push:
    branches: [main]
    paths:
      - 'whollyowned/sites/**'
      - 'modules/static-site/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::WHOLLYOWNED_ACCOUNT_ID:role/sites-terraform-role
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: ./whollyowned/sites
        run: terraform init

      - name: Terraform Plan
        working-directory: ./whollyowned/sites
        run: terraform plan -out=tfplan

      - name: Terraform Apply
        working-directory: ./whollyowned/sites
        run: terraform apply -auto-approve tfplan
```

**Benefits**:
- No long-lived AWS credentials in GitHub
- Short-lived session tokens (1 hour)
- Scoped permissions per layer (sites role can't modify domains)

---

## Disaster Recovery

### State File Recovery

- **S3 versioning enabled**: Recover from accidental deletions (90-day retention)
- **Recovery**: Restore previous version from S3
- **Local backups**: Keep local `.tfstate.backup` files until migration complete

### Infrastructure Recovery

All infrastructure is defined as code:
1. State files backed up in versioned S3 bucket
2. Terraform code in Git (version controlled)
3. Recovery: `terraform plan` + `terraform apply` (idempotent)

### Certificate Recovery

- **ACM automatic renewal**: 60 days before expiration
- **If renewal fails**: ACM sends email alerts, manual re-validation via Route53 DNS

---

## Next Steps

After deploying the whollyowned account:

1. **Verify account resources**:
   ```bash
   aws s3 ls --profile whollyowned-admin
   aws route53 list-hosted-zones --profile whollyowned-admin
   aws cloudfront list-distributions --profile whollyowned-admin
   ```

2. **Test website access**:
   ```bash
   curl -I https://camdenwander.com
   # Expected: HTTP/2 200, x-cache header from CloudFront
   ```

3. **Set up monitoring**: CloudWatch alarms for error rates, CloudFront logs (future)

4. **Configure billing alerts**: Per-account cost monitoring (future)

---

## References

### Layer Documentation

- [rbac/CLAUDE.md](./rbac/CLAUDE.md)
- [tfstate-backend/CLAUDE.md](./tfstate-backend/CLAUDE.md)
- [domains/CLAUDE.md](./domains/CLAUDE.md)
- [sites/CLAUDE.md](./sites/CLAUDE.md)

### Parent Documentation

- [../CLAUDE.md](../CLAUDE.md) - Overall architecture
- [../management/CLAUDE.md](../management/CLAUDE.md) - Management account overview

### Module Documentation

- [../modules/domain/CLAUDE.md](../modules/domain/CLAUDE.md) - Domain module (Route53 + ACM)
- [../modules/static-site/CLAUDE.md](../modules/static-site/CLAUDE.md) - Static site module (S3 + CloudFront)

### AWS Documentation

- [AWS Organizations Multi-Account Strategy](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
- [Route53 DNS Best Practices](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/best-practices-dns.html)
- [CloudFront Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/best-practices.html)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)

---

**Account**: noise2signal-llc-whollyowned
**Last Updated**: 2026-01-26
**Maintainer**: Noise2Signal LLC Infrastructure Team
