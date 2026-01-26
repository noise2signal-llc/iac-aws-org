# Noise2Signal LLC - Multi-Account AWS Organizations Architecture

## Executive Summary

This document provides a comprehensive overview of the Terraform infrastructure architecture for Noise2Signal LLC's AWS Organization. The design separates concerns across **multiple AWS accounts and infrastructure layers within a single repository**, enabling secure multi-tenancy, clear ownership boundaries, and scalable management of wholly-owned and commissioned website infrastructure.

**Key Design Principles:**
- **Account Isolation**: Management and workload accounts with clear separation of concerns
- **Separation of Concerns**: Infrastructure organized into discrete layers per account
- **Reusability**: Shared patterns extracted into local modules
- **Security**: SCPs, fine-grained IAM permissions, encryption by default
- **Scalability**: Variable-driven multi-site deployment, multi-account structure
- **Cost Transparency**: Cost allocation tags for all resources

---

## AWS Organization Structure

### Account Hierarchy

```
noise2signal-llc (Organization Root)
├── Management OU
│   └── noise2signal-llc-management (Management Account)
│       • AWS Organizations
│       • IAM Identity Center (AWS SSO)
│       • Service Control Policies
│       • Consolidated billing
│       • Route53 domain registrations (domains only, NOT zones)
│
├── Workloads OU
│   ├── Production OU
│   │   └── noise2signal-llc-whollyowned (Production Account)
│   │       • Route53 hosted zones
│   │       • ACM certificates
│   │       • S3, CloudFront (website infrastructure)
│   │       • IAM roles + OIDC
│   │
│   └── Development OU (future: staging accounts)
│
├── Clients OU (future: commissioned work accounts)
│   ├── noise2signal-llc-client-acme (future)
│   └── noise2signal-llc-client-beta (future)
│
└── Sandbox OU (future: experimentation, non-production testing)
```

**Account Responsibilities**:

| Account | Purpose | Key Resources | State Backend |
|---------|---------|---------------|---------------|
| **Management** | Organization governance, SSO, billing | AWS Org, SCPs, IAM Identity Center, domain registrations | S3 in management account |
| **Whollyowned** | N2S brand websites (production) | Route53 zones, ACM, S3, CloudFront | S3 in whollyowned account |
| **Client accounts** (future) | Commissioned work (separate billing) | Same as whollyowned | S3 in each client account |

---

## Repository Architecture

### Single Repository, Multi-Account Structure

All infrastructure is managed in a **single Git repository** (`iac-aws`) with account-specific directories:

```
iac-aws/
├── CLAUDE.md                       # This file (overall architecture)
├── .gitignore                      # Ignores *.tfstate, *.tfvars
├── README.md                       # Repository overview
│
├── management/                     # Management Account
│   ├── CLAUDE.md                   # Account overview
│   ├── organization/               # Layer 0: AWS Organization, OUs, accounts
│   ├── sso/                        # Layer 1: IAM Identity Center
│   ├── scp/                        # Layer 2: Service Control Policies
│   └── tfstate-backend/            # Layer 3: State backend (management)
│
├── whollyowned/                    # Whollyowned Account
│   ├── CLAUDE.md                   # Account overview
│   ├── rbac/                       # Layer 0: IAM roles + OIDC
│   ├── tfstate-backend/            # Layer 1: State backend (whollyowned)
│   ├── domains/                    # Layer 2: Route53 zones + ACM
│   └── sites/                      # Layer 3: S3 + CloudFront + DNS
│
└── modules/                        # Shared modules (cross-account)
    ├── domain/                     # Route53 zone + ACM pattern
    └── static-site/                # S3 + CloudFront + DNS pattern
```

---

## Deployment Sequence

### Phase 1: Management Account Bootstrap

**Prerequisites**:
- AWS account created (this becomes the management account)
- Root user access for initial setup
- AWS CLI configured with management account admin credentials

**Deployment Order**:

```
┌─────────────────────────────────────────────────────────────┐
│  management/organization/                                   │
│  Layer 0: AWS Organization, OUs, Accounts                   │
│  ─────────────────────────────────────────────────────────  │
│  • Enable AWS Organizations                                 │
│  • Create OU structure (Management, Workloads, Clients)     │
│  • Create whollyowned account                               │
│  • Configure consolidated billing                           │
│                                                             │
│  Auth: Root user / admin credentials, Local state          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  management/sso/                                            │
│  Layer 1: IAM Identity Center (AWS SSO)                     │
│  ─────────────────────────────────────────────────────────  │
│  • Enable IAM Identity Center                               │
│  • Create permission sets (Admin, ReadOnly)                 │
│  • Create SSO user for boss (non-root admin access)         │
│  • Assign permissions to accounts                           │
│                                                             │
│  Auth: Root user / admin credentials, Local state          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  management/scp/                                            │
│  Layer 2: Service Control Policies                          │
│  ─────────────────────────────────────────────────────────  │
│  • Create SCPs for Workloads OU (restrictive)               │
│  • Create SCPs for Management OU (minimal restrictions)     │
│  • Apply to OUs (not individual accounts)                   │
│  • Constrain services, regions, actions                     │
│                                                             │
│  Auth: Root user / admin credentials, Local state          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  management/tfstate-backend/                                │
│  Layer 3: Terraform State Backend (optional, last)          │
│  ─────────────────────────────────────────────────────────  │
│  • S3 bucket for management account state                   │
│  • DynamoDB table for state locking                         │
│  • Encrypt, version, lifecycle policies                     │
│  • Migrate management layers to remote state                │
│                                                             │
│  Auth: SSO admin or IAM role, Local → Remote state         │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Whollyowned Account Bootstrap

**Prerequisites**:
- Phase 1 complete (whollyowned account created)
- Access to whollyowned account (via SSO or assume-role from management)

**Deployment Order**:

```
┌─────────────────────────────────────────────────────────────┐
│  whollyowned/rbac/                                          │
│  Layer 0: IAM Roles + OIDC Provider                         │
│  ─────────────────────────────────────────────────────────  │
│  • GitHub OIDC provider                                     │
│  • IAM roles for each layer (tfstate, domains, sites)       │
│  • Least-privilege policies per role                        │
│  • Trust policy for GitHub Actions                          │
│                                                             │
│  Auth: SSO admin, Local state                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  whollyowned/tfstate-backend/                               │
│  Layer 1: Terraform State Backend (optional, last)          │
│  ─────────────────────────────────────────────────────────  │
│  • S3 bucket for whollyowned account state                  │
│  • DynamoDB table for state locking                         │
│  • Migrate whollyowned layers to remote state               │
│                                                             │
│  Auth: Assumes tfstate-terraform-role, Local → Remote      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  whollyowned/domains/                                       │
│  Layer 2: Route53 Zones + ACM Certificates                  │
│  ─────────────────────────────────────────────────────────  │
│  • Route53 hosted zones (public DNS)                        │
│  • ACM certificates (us-east-1, DNS validation)             │
│  • CAA records (restrict to AWS)                            │
│  • Uses domain module for each domain                       │
│                                                             │
│  Auth: Assumes domains-terraform-role                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  whollyowned/sites/                                         │
│  Layer 3: Website Infrastructure                            │
│  ─────────────────────────────────────────────────────────  │
│  • S3 buckets (primary + www redirect)                      │
│  • CloudFront distributions (CDN)                           │
│  • Route53 A/AAAA records (→ CloudFront)                    │
│  • Uses static-site module for each site                    │
│                                                             │
│  Auth: Assumes sites-terraform-role                        │
└─────────────────────────────────────────────────────────────┘
```

### Phase 3: Cross-Account Wiring

**Manual Step**: Update domain registrations in management account with NS records from whollyowned account

```bash
# In whollyowned account: Get NS records from hosted zone
aws route53 list-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value"

# In management account: Update domain nameservers
aws route53domains update-domain-nameservers \
  --region us-east-1 \
  --domain-name camdenwander.com \
  --nameservers Name=ns-123.awsdns-12.com Name=ns-456.awsdns-45.net ...
```

**Future Enhancement**: Automate with Terraform data sources or AWS Lambda

---

## State Management

### Per-Account State Backends

Each account has its own S3 backend for isolation and blast radius control:

**Management Account**:
```
s3://n2s-terraform-state-management/
└── management/
    ├── organization.tfstate
    ├── sso.tfstate
    ├── scp.tfstate
    └── tfstate-backend.tfstate (after migration)
```

**Whollyowned Account**:
```
s3://n2s-terraform-state-whollyowned/
└── whollyowned/
    ├── rbac.tfstate
    ├── tfstate-backend.tfstate (after migration)
    ├── domains.tfstate
    └── sites.tfstate
```

**Future Client Accounts**:
```
s3://n2s-terraform-state-client-acme/
└── client-acme/
    ├── rbac.tfstate
    ├── domains.tfstate
    └── sites.tfstate
```

**State Backend Details** (per account):
- **Encryption**: AES256 server-side encryption
- **Versioning**: Enabled (90-day retention for old versions)
- **Locking**: DynamoDB table per bucket
- **Access**: Restricted to account's IAM roles only

### Migration Workflow

1. **Initial deployment**: All layers use local state
2. **Deploy tfstate-backend layer** (per account)
3. **Uncomment `backend.tf`** in each layer (per account)
4. **Run `terraform init -migrate-state`** in each layer
5. **Verify migration**: `aws s3 ls s3://<bucket>/`
6. **Delete local state files**: `rm terraform.tfstate*`

---

## Cross-Account Dependencies

### Route53 Domain Registration → Hosted Zone

**Challenge**: Domain registrations live in management account, hosted zones in whollyowned account

**Resolution Pattern**:

```hcl
# In whollyowned/domains layer: Create hosted zone
resource "aws_route53_zone" "site" {
  name = "camdenwander.com"
  tags = local.common_tags
}

# Output the nameservers
output "nameservers" {
  value = aws_route53_zone.site.name_servers
}

# In management account: Manually update domain registration
# (Future: Terraform data source or custom resource)
```

**Manual Step**: Update domain nameservers in Route53 domain registrations after hosted zone creation

**Future Enhancement**: Cross-account Terraform remote state lookup or automation via Lambda

### ACM Certificate → CloudFront

**Challenge**: ACM certificates and CloudFront distributions must be in same account

**Resolution**: Both live in whollyowned account (no cross-account dependency)

```hcl
# In whollyowned/sites layer: Discover ACM certificate
data "aws_acm_certificate" "site" {
  provider    = aws.us_east_1
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Use in CloudFront distribution
resource "aws_cloudfront_distribution" "site" {
  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.site.arn
    ssl_support_method  = "sni-only"
  }
}
```

---

## Security Architecture

### Service Control Policies (SCPs)

**Management OU SCPs** (minimal restrictions):
- Allow all IAM, Organizations, IAM Identity Center operations
- Allow S3, DynamoDB (for state backend)
- Allow Route53 domain registration operations
- Deny destructive organization actions (delete org, leave org)

**Workloads OU SCPs** (restrictive):
- Allow only: IAM, STS, S3, DynamoDB, Route53, ACM, CloudFront, CloudWatch
- Deny all other services (explicit deny-by-default)
- Enforce us-east-1 for global services (CloudFront, ACM)
- Deny root user actions (force SSO/IAM roles)

**Clients OU SCPs** (future, similar to Workloads):
- Same service restrictions as Workloads OU
- Additional cost control policies (instance types, regions)

### IAM Identity Center (AWS SSO)

**Permission Sets**:
- **AdministratorAccess**: Full admin (boss only, break-glass)
- **PowerUserAccess**: Developers, infrastructure team
- **ReadOnlyAccess**: Auditors, finance team

**Users**:
- Boss SSO user (AdministratorAccess to all accounts)
- Future: Additional team members as needed

**MFA**: Enforced for all SSO users

### IAM Roles (Per Account)

**Management Account**:
- Terraform roles: Not needed initially (use SSO admin)
- Future: Terraform execution roles for GitHub Actions

**Whollyowned Account**:
- `rbac-terraform-role`: Bootstrap role (creates other roles)
- `tfstate-terraform-role`: State backend management
- `domains-terraform-role`: Route53 + ACM management
- `sites-terraform-role`: S3 + CloudFront management

**All roles** trust GitHub OIDC provider for CI/CD authentication

### GitHub OIDC Integration

**Per-Account OIDC Provider**:

Each account has its own GitHub OIDC provider and IAM roles:

```hcl
# In whollyowned/rbac layer
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# Trust policy for Terraform roles
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
      values   = ["repo:noise2signal/iac-aws:*"]
    }
  }
}
```

**Benefits**:
- No long-lived AWS credentials in GitHub
- Short-lived session tokens (1 hour)
- Per-account isolation (blast radius control)

### Encryption

**At Rest**:
- S3 buckets: AES256 (all buckets, all accounts)
- Terraform state: Encrypted in S3
- DynamoDB: AWS-managed keys

**In Transit**:
- HTTPS enforced: CloudFront redirects HTTP → HTTPS
- TLS 1.2+ minimum
- ACM certificates (automatic renewal)

---

## Cost Allocation Strategy

### Cost Centers & Tagging

All resources tagged with:

```hcl
tags = {
  Organization = "noise2signal-llc"
  Account      = "whollyowned"  # or "management", "client-acme"
  CostCenter   = "whollyowned"  # or "infrastructure", "client-acme"
  Environment  = "production"   # or "development", "staging"
  ManagedBy    = "terraform"
  Layer        = "domains"      # or "sites", "scp", etc.
}
```

**Cost Centers**:
- `infrastructure`: Management account resources (org, SSO, SCPs)
- `whollyowned`: N2S brand websites
- `client-{name}`: Client commissioned work (future)

### Cost Monitoring

**Consolidated Billing**: Enabled in management account (organization payer)

**Cost Allocation Tags**: Activated in management account:
- `CostCenter`
- `Account`
- `Environment`
- `Layer`

**Billing Alarms**: Per-account CloudWatch alarms (future)

**Monthly Cost Estimates**:

**Management Account** (~$1.50/month):
```
AWS Organizations:           Free
IAM Identity Center:         Free
Service Control Policies:    Free
Route53 domain registration: ~$12/year ($1/month per domain)
S3 state backend:            ~$0.10
DynamoDB state locking:      ~$0.25
──────────────────────────────
Total:                       ~$1.35/month (1 domain)
```

**Whollyowned Account** (~$2-6/month per site):
```
S3 state backend:            ~$0.10
DynamoDB state locking:      ~$0.25
Route53 hosted zone:         ~$0.50
ACM certificate:             Free (with CloudFront)
S3 website storage:          ~$0.02/GB
CloudFront:                  ~$1-5 (traffic-dependent)
──────────────────────────────
Total per site:              ~$1.87-5.87/month
```

**Total Organization** (1 domain, 1 site): ~$3-7/month

---

## Multi-Tenancy Strategy

### Account-Level Separation

**Wholly-Owned Work** (N2S IP):
- Account: `noise2signal-llc-whollyowned`
- OU: `Workloads/Production`
- Billing: `whollyowned` cost center
- Repository: `iac-aws` (this repo, `/whollyowned/` directory)

**Commissioned Work** (Client IP, future):
- Account: `noise2signal-llc-client-{name}` (separate account per client)
- OU: `Clients`
- Billing: `client-{name}` cost center (separate bills)
- Repository: `iac-aws` (this repo, `/clients/{name}/` directory) OR separate repo

**Design Principle**: Each client gets a separate AWS account for:
- **Billing isolation**: Client costs clearly separated
- **Security boundary**: Clients cannot access each other's resources
- **Blast radius control**: Issues in one account don't affect others
- **Ownership transfer**: Easy to transfer account to client later

### Repository Strategy for Clients

**Option A** (Recommended): Separate repository per client
```
iac-aws/                    # N2S internal (management + whollyowned)
iac-aws-client-acme/        # Client ACME (forked template)
iac-aws-client-beta/        # Client Beta (forked template)
```

**Option B**: Single repository, per-client directories
```
iac-aws/
├── management/
├── whollyowned/
└── clients/
    ├── acme/               # Client ACME layers
    └── beta/               # Client Beta layers
```

**Recommendation**: Start with Option A for stronger access control and IP separation

---

## Deployment Workflow

### Initial Bootstrap Commands

**Phase 1: Management Account**

```bash
# Clone repository
git clone https://github.com/noise2signal/iac-aws.git
cd iac-aws

# Configure AWS CLI with management account root/admin
aws configure --profile management-admin

# Deploy organization layer
cd management/organization
terraform init
terraform apply
# Note: whollyowned account ID from outputs

# Deploy SSO layer
cd ../sso
terraform init
terraform apply
# Note: Create SSO user, configure MFA

# Switch to SSO credentials
aws sso login --profile management-sso

# Deploy SCP layer
cd ../scp
terraform init
terraform apply

# Deploy state backend (optional, last)
cd ../tfstate-backend
terraform init
terraform apply
# Migrate management layers to remote state
```

**Phase 2: Whollyowned Account**

```bash
# Configure AWS CLI with whollyowned account access (via SSO)
aws sso login --profile whollyowned-admin

# Deploy RBAC layer
cd whollyowned/rbac
terraform init
terraform apply
# Note: IAM role ARNs from outputs

# Deploy state backend (optional, last)
cd ../tfstate-backend
terraform init
terraform apply
# Migrate whollyowned layers to remote state

# Deploy domains layer
cd ../domains
terraform init
terraform apply
# Wait for ACM certificate validation (5-10 min)

# Deploy sites layer
cd ../sites
terraform init
terraform apply
# Wait for CloudFront deployment (15-30 min)

# Upload website content
aws s3 sync ./website/ s3://camdenwander.com/ --delete
aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"
```

**Phase 3: Cross-Account Wiring**

```bash
# Get NS records from whollyowned hosted zone
aws route53 list-hosted-zones --profile whollyowned-admin
aws route53 list-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value"

# Update domain nameservers in management account
aws route53domains update-domain-nameservers \
  --region us-east-1 \
  --profile management-admin \
  --domain-name camdenwander.com \
  --nameservers Name=ns-123.awsdns-12.com Name=ns-456.awsdns-45.net ...
```

### CI/CD (GitHub Actions)

**Per-Account Workflows**:

```yaml
# .github/workflows/management-scp.yml
name: Management - SCP Layer

on:
  push:
    branches: [main]
    paths: ['management/scp/**']

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
          role-to-assume: arn:aws:iam::MGMT_ACCOUNT_ID:role/scp-terraform-role
          aws-region: us-east-1
      - name: Terraform Init
        working-directory: ./management/scp
        run: terraform init
      - name: Terraform Apply
        working-directory: ./management/scp
        run: terraform apply -auto-approve
```

```yaml
# .github/workflows/whollyowned-sites.yml
name: Whollyowned - Sites Layer

on:
  push:
    branches: [main]
    paths: ['whollyowned/sites/**']

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
      - name: Terraform Apply
        working-directory: ./whollyowned/sites
        run: terraform apply -auto-approve
```

---

## Future Roadmap

### Short-term (Next 3 Months)
- [x] Design multi-account architecture
- [ ] Create Terraform configurations for all layers
- [ ] Deploy management account (organization, SSO, SCPs)
- [ ] Deploy whollyowned account (domains, sites)
- [ ] Implement GitHub Actions CI/CD
- [ ] Set up billing alarms per account

### Medium-term (3-6 Months)
- [ ] Add CloudWatch alarms for website error rates
- [ ] Implement CloudFront access logging
- [ ] Create development/staging account (under Workloads/Development OU)
- [ ] Add Lambda@Edge for advanced routing
- [ ] Automate cross-account NS record updates

### Long-term (6-12 Months)
- [ ] Create first client account (Clients OU)
- [ ] Multi-region S3 state replication (disaster recovery)
- [ ] AWS Config compliance scanning (per account)
- [ ] Terraform Cloud integration (centralized management)
- [ ] Cross-account IAM role assumption for centralized operations

---

## Troubleshooting Guide

### Common Issues

**Issue**: Cannot access whollyowned account
- **Cause**: SSO not configured, permission set not assigned
- **Resolution**: Check IAM Identity Center, assign AdministratorAccess to boss user

**Issue**: SCP blocks legitimate action in management account
- **Cause**: Overly restrictive SCP applied to Management OU
- **Resolution**: Review SCP, ensure management account has minimal restrictions

**Issue**: Cross-account NS record update fails
- **Cause**: Manual process, not yet automated
- **Resolution**: Manually update via AWS console or CLI, document for automation

**Issue**: Terraform state locking timeout
- **Cause**: Previous run failed without releasing lock
- **Resolution**: `terraform force-unlock <LOCK_ID>` in affected account

**Issue**: ACM certificate validation stuck
- **Cause**: NS records not updated in management account
- **Resolution**: Complete Phase 3 cross-account wiring first

**Issue**: Role assumption failure (GitHub Actions)
- **Cause**: OIDC provider not created, trust policy misconfigured
- **Resolution**: Check whollyowned/rbac layer deployment, verify trust policy

---

## References

### Internal Documentation
- [management/CLAUDE.md](./management/CLAUDE.md) - Management account overview
- [management/organization/CLAUDE.md](./management/organization/CLAUDE.md) - Organization layer
- [management/sso/CLAUDE.md](./management/sso/CLAUDE.md) - IAM Identity Center layer
- [management/scp/CLAUDE.md](./management/scp/CLAUDE.md) - SCP layer
- [whollyowned/CLAUDE.md](./whollyowned/CLAUDE.md) - Whollyowned account overview
- [whollyowned/rbac/CLAUDE.md](./whollyowned/rbac/CLAUDE.md) - RBAC layer
- [whollyowned/domains/CLAUDE.md](./whollyowned/domains/CLAUDE.md) - Domains layer
- [whollyowned/sites/CLAUDE.md](./whollyowned/sites/CLAUDE.md) - Sites layer
- [modules/domain/CLAUDE.md](./modules/domain/CLAUDE.md) - Domain module
- [modules/static-site/CLAUDE.md](./modules/static-site/CLAUDE.md) - Static site module

### External Resources
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [AWS Organizations Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices.html)
- [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [Terraform AWS Multi-Account](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

---

**Document Version**: 3.0 (Multi-Account AWS Organizations Architecture)
**Last Updated**: 2026-01-26
**Maintained By**: Noise2Signal LLC Infrastructure Team
