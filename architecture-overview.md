# Noise2Signal LLC - Terraform Single-Repository Architecture

## Executive Summary

This document provides a comprehensive overview of the Terraform infrastructure architecture for Noise2Signal LLC's AWS account. The design separates concerns across **infrastructure layers within a single repository**, enabling modular development, clear ownership boundaries, and scalable management of wholly-owned and commissioned website infrastructure.

**Key Design Principles:**
- **Separation of Concerns**: Infrastructure organized into discrete layers
- **Reusability**: Shared patterns extracted into local modules
- **Security**: Fine-grained IAM permissions per layer, encryption by default
- **Scalability**: Variable-driven multi-site deployment within layers
- **Client IP Separation**: Clear boundaries between Noise2Signal and client-owned properties

---

## Repository Architecture

### Single Repository, Multi-Layer Structure

All infrastructure is managed in a **single Git repository** (`iac-aws`) with layers organized by deployment order and concern:

```
iac-aws/
├── scp/                     # Layer 0: Service Control Policies
├── rbac/                    # Layer 1: IAM Roles
├── tfstate-backend/         # Layer 2: S3 + DynamoDB State Backend
├── domains/                 # Layer 3: Route53 + ACM
├── sites/                   # Layer 4: S3 + CloudFront + DNS Records
└── modules/
    ├── domain/              # Route53 + ACM module
    └── static-site/         # S3 + CloudFront + DNS module
```

### Five-Layer Infrastructure Stack

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 0: scp                                               │
│  Purpose: Service Control Policies (bootstrap)             │
│  ─────────────────────────────────────────────────────────  │
│  • Constrain AWS account to actively used services         │
│  • Enforce regional restrictions (us-east-1)                │
│  • Reduce attack surface through service allow-listing     │
│                                                             │
│  Deployed First: Admin credentials, local state            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: rbac                                              │
│  Purpose: IAM roles for Terraform execution                │
│  ─────────────────────────────────────────────────────────  │
│  • One IAM role per layer (scp, tfstate, domains, sites)   │
│  • GitHub OIDC provider (federated auth for CI/CD)         │
│  • Scoped permissions (principle of least privilege)       │
│                                                             │
│  Deployed Second: Admin credentials, local state           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: tfstate-backend (Optional, deployed last)         │
│  Purpose: Remote state storage and locking                 │
│  ─────────────────────────────────────────────────────────  │
│  • S3 state backend bucket                                  │
│  • DynamoDB state locking table                            │
│  • Can be deployed last, all layers migrate from local     │
│                                                             │
│  Deployed Last (Optional): Assumes tfstate-terraform-role  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: domains                                           │
│  Purpose: Domain ownership and SSL/TLS certificates        │
│  ─────────────────────────────────────────────────────────  │
│  • Route53 hosted zones                                     │
│  • ACM certificates (us-east-1, DNS validation)            │
│  • CAA records (optional)                                   │
│  • Uses domain module for each domain                       │
│                                                             │
│  Deployed Third: Assumes domains-terraform-role            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: sites                                             │
│  Purpose: Website infrastructure (wholly-owned sites)       │
│  ─────────────────────────────────────────────────────────  │
│  • S3 buckets (primary + www redirect)                      │
│  • CloudFront distributions (CDN)                           │
│  • Route53 A/AAAA records (→ CloudFront)                    │
│  • Uses static-site module (optional) for each site         │
│                                                             │
│  Deployed Fourth: Assumes sites-terraform-role             │
└─────────────────────────────────────────────────────────────┘
```

### Module Organization (Local Modules)

```
┌──────────────────────────────────────────┐
│  modules/domain/                         │
│  Route53 zone + ACM certificate pattern  │
│  Consumed by: domains layer              │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  modules/static-site/                    │
│  S3 + CloudFront + DNS pattern           │
│  Consumed by: sites layer                │
└──────────────────────────────────────────┘

Source method: Local path (../modules/domain, ../modules/static-site)
No versioning complexity - single repo, single source of truth
```

---

## State Management

### State Storage Strategy

**Initial Deployment**: All layers use **local state files** (`.tfstate` in each layer directory, gitignored)

**After tfstate-backend Deployment**: All layers migrate to **remote S3 backend**

```
s3://noise2signal-terraform-state/
└── noise2signal/
    ├── scp.tfstate                 # Layer 0 state
    ├── rbac.tfstate                # Layer 1 state
    ├── tfstate-backend.tfstate     # Layer 2 state (after migration)
    ├── domains.tfstate             # Layer 3 state
    └── sites.tfstate               # Layer 4 state

Future: client-<name>/ prefix for commissioned work
```

**State Backend Details**:
- **S3 Bucket**: `noise2signal-terraform-state`
- **DynamoDB Table**: `noise2signal-terraform-state-lock`
- **Encryption**: AES256 server-side encryption (all state files)
- **Versioning**: Enabled (90-day retention for old versions)
- **Access Control**: Restricted to Terraform execution IAM roles only

### Migration Workflow

1. **Initial deployment**: All layers use local state
2. **Deploy tfstate-backend layer** (creates S3 + DynamoDB)
3. **Uncomment `backend.tf`** in each layer
4. **Run `terraform init -migrate-state`** in each layer
5. **Verify migration**: `aws s3 ls s3://noise2signal-terraform-state/noise2signal/`
6. **Delete local state files**: `rm terraform.tfstate terraform.tfstate.backup`

---

## Cross-Layer Dependencies

### Dependency Resolution Pattern

**Approach**: AWS data sources (not remote state lookups)

```hcl
# In sites layer: Discover hosted zone from domains layer
data "aws_route53_zone" "site" {
  name = var.domain_name
}

# Discover ACM certificate from domains layer
data "aws_acm_certificate" "site" {
  provider    = aws.us_east_1
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Usage:
# zone_id = data.aws_route53_zone.site.zone_id
# certificate_arn = data.aws_acm_certificate.site.arn
```

**Design Rationale**:
- **Simpler** than remote state dependencies
- **More reliable** (AWS data sources are well-tested)
- **Looser coupling** (layers don't depend on each other's state)
- **Can evolve** to remote state lookups later if needed

---

## IAM Role Architecture

### One Role Per Layer

Each layer assumes a dedicated IAM role with scoped permissions (created in `rbac` layer):

| Layer | Role Name | Allowed Services | Permissions Scope |
|-------|-----------|-----------------|-------------------|
| **Layer 0: scp** | `scp-terraform-role` | AWS Organizations | SCP management only |
| **Layer 1: rbac** | N/A (uses admin) | IAM | Role/policy creation |
| **Layer 2: tfstate-backend** | `tfstate-backend-terraform-role` | S3, DynamoDB | State bucket + lock table |
| **Layer 3: domains** | `domains-terraform-role` | Route53, ACM | DNS zones + certificates |
| **Layer 4: sites** | `sites-terraform-role` | S3, CloudFront, Route53 | Website infrastructure |

**All roles** also have access to the state backend (S3 + DynamoDB) via shared policy.

### GitHub OIDC Integration

All Terraform roles trust the GitHub OIDC provider (created in `rbac` layer):

```hcl
# Trust policy allows GitHub Actions to assume role
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:noise2signal/*:*"
    }
  }
}
```

**Benefits**:
- No long-lived AWS credentials in GitHub
- Short-lived session tokens (1 hour)
- Federated authentication (secure)

---

## Deployment Workflow

### Initial Infrastructure Bootstrap

**Step 0: Deploy SCP layer**
```bash
cd scp
terraform init                  # Local state
terraform apply
# Account is now constrained to allowed services
```

**Step 1: Deploy RBAC layer**
```bash
cd rbac
terraform init                  # Local state
terraform apply
# All Terraform execution roles now exist
```

**Step 2: Deploy domains layer**
```bash
cd domains
terraform init                  # Local state, assumes domains-terraform-role
terraform apply
# Wait for ACM certificate validation (5-10 minutes)
```

**Step 3: Deploy sites layer**
```bash
cd sites
terraform init                  # Local state, assumes sites-terraform-role
terraform apply
# Wait for CloudFront deployment (15-30 minutes)
```

**Step 4: Upload website content**
```bash
aws s3 sync ./website/ s3://camdenwander.com/ --delete
aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"
```

**Step 5 (Optional): Deploy tfstate-backend and migrate**
```bash
cd tfstate-backend
terraform init                  # Local state, assumes tfstate-terraform-role
terraform apply

# Migrate all layers to remote state
for layer in scp rbac tfstate-backend domains sites; do
  cd $layer
  # Uncomment backend.tf
  terraform init -migrate-state
  cd ..
done
```

### Adding a New Site

**Prerequisites:**
- Domain transferred to Route53 or ready for new zone

**Process:**
1. **Add to domains layer**
   ```hcl
   # domains/terraform.tfvars
   domains = {
     "camdenwander.com" = { ... },
     "newdomain.com" = { ... },  # Added
   }
   ```
   Apply changes, wait for certificate validation.

2. **Add to sites layer**
   ```hcl
   # sites/terraform.tfvars
   sites = {
     "camdenwander.com" = { ... },
     "newdomain.com" = { ... },  # Added
   }
   ```
   Apply changes, wait for CloudFront deployment.

3. **Upload content**
   ```bash
   aws s3 sync ./new-site/ s3://newdomain.com/
   ```

**Timeline**: ~45 minutes (certificate validation + CloudFront deployment)

---

## Security Architecture

### Layer 0: Service Control Policies

**Purpose**: Account-level service constraints

**Allowed Services**:
- IAM, STS, Organizations (core)
- S3, DynamoDB (state backend)
- Route53, ACM (DNS + certificates)
- CloudFront (CDN)

**Enforcement**:
- Explicit allow-list (deny by default)
- Regional restrictions (primarily us-east-1)
- Applies to all principals (defense in depth)

### Layer 1: IAM Roles

**Purpose**: Terraform execution with least privilege

**Per-layer scoping**:
- Each role can ONLY manage its layer's resources
- No cross-layer IAM permissions
- State backend access shared via common policy

**GitHub OIDC**:
- No long-lived credentials
- Session tokens expire after 1 hour
- Repository-scoped trust policy

### Encryption at Rest
- **S3 buckets**: AES256 server-side encryption (all buckets)
- **Terraform state**: Encrypted in S3 (all state files)
- **DynamoDB**: AWS-managed keys

### Encryption in Transit
- **HTTPS enforced**: All CloudFront distributions redirect HTTP → HTTPS
- **TLS 1.2+**: Minimum protocol version
- **Certificate management**: AWS Certificate Manager (automatic renewal)

### Access Control
- **S3 buckets**: CloudFront Origin Access Control (OAC), not public
- **IAM roles**: Least privilege, scoped to specific resources where possible
- **State backend**: Restricted to Terraform execution roles only

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
- **Registrar lock**: Enabled (prevents unauthorized transfers)
- **DNSSEC**: Optional (can be enabled for enhanced security)

---

## Cost Structure

### Infrastructure Costs (Monthly Estimates)

**Layer 0: SCP**
- Service Control Policies: **Free**

**Layer 1: RBAC**
- IAM roles and policies: **Free**
- GitHub OIDC provider: **Free**

**Layer 2: Tfstate Backend (One-time setup)**
- S3 state bucket: ~$0.10
- DynamoDB state locking: ~$0.25
- **Total**: ~$0.35/month

**Layer 3: Domains (Per domain)**
- Route53 hosted zone: $0.50/month
- Route53 queries: ~$0.40 per 1M queries
- ACM certificates: **Free** (when used with CloudFront)
- **Total per domain**: ~$0.90/month + query costs

**Layer 4: Sites (Per site)**
- S3 storage: ~$0.023/GB
- S3 requests: ~$0.005 per 1K requests
- CloudFront data transfer: ~$0.085/GB (PriceClass_100)
- CloudFront requests: ~$0.0075 per 10K HTTPS requests
- **Total per site**: $1-5/month (varies by traffic)

**Total for 1 Wholly-Owned Site (camdenwander.com)**:
```
Layer 0-1:    Free
Layer 2:      $0.35 (state backend)
Layer 3:      $0.90 (domain)
Layer 4:      $1-5  (site, traffic-dependent)
─────────────────────────
Total:        ~$2.25-$6.25/month
```

**Scaling**: Each additional site adds ~$1.90/month (domain) + $1-5/month (traffic)

### Cost Optimization
- CloudFront PriceClass_100 (US/Canada/Europe only)
- S3 lifecycle policies for old state versions
- Route53 query monitoring for anomalies
- Pay-per-request DynamoDB (vs provisioned capacity)

---

## Multi-Tenancy Strategy

### Wholly-Owned vs. Commissioned Work

**Repository-level separation remains**:

```
Wholly-Owned (Noise2Signal IP):
- iac-aws (this repository)
  → sites layer manages: camdenwander.com, etc.
  → State: s3://.../noise2signal/sites.tfstate

Commissioned (Client IP):
- iac-aws-client-acme (separate repository, cloned from template)
  → sites layer manages: client-acme.com, etc.
  → State: s3://.../client-acme/sites.tfstate
  → Separate repo = separate access control
```

**Design Principle**: Each client's infrastructure is a **separate GitHub repository** (cloned from this template) with:
- Separate state file prefix in S3 (isolation, blast radius control)
- Separate access controls (client sees only their config)
- Separate tagging for billing/ownership tracking
- Same layer structure for consistency

**Future Consideration**: Client work may move to separate AWS accounts (cross-account infrastructure)

---

## Disaster Recovery

### State File Recovery
- **S3 versioning**: Enabled (recover from accidental deletions)
- **Lifecycle policy**: Retain old versions for 90 days
- **Backup strategy**: S3 bucket replication to secondary region (future enhancement)

### Infrastructure Recovery
All infrastructure is defined as code:
1. State files backed up in versioned S3 bucket (after migration)
2. Terraform code in Git (version controlled)
3. Local state backups (`.tfstate.backup` files if migration fails)
4. Recovery: `terraform plan` + `terraform apply` (idempotent)

### Certificate Recovery
- ACM handles automatic renewal (60 days before expiration)
- If renewal fails, ACM sends email alerts
- Manual re-validation possible via Route53 DNS records

---

## Development Workflow

### Local Development

1. Clone repository
   ```bash
   git clone https://github.com/noise2signal/iac-aws.git
   cd iac-aws
   ```

2. Navigate to layer
   ```bash
   cd domains  # or sites, rbac, etc.
   ```

3. Assume layer's IAM role (via AWS CLI or SSO)
   ```bash
   aws sts assume-role \
     --role-arn arn:aws:iam::ACCOUNT_ID:role/domains-terraform-role \
     --role-session-name terraform-session
   ```

4. Make changes to `.tf` files

5. Run `terraform plan` to preview changes

6. Run `terraform apply` to deploy (dev/testing only)

7. Commit changes to feature branch

8. Open pull request for review

### CI/CD (GitHub Actions)

1. PR opened → Automated `terraform plan` runs (per layer if files changed)
2. Plan output posted as PR comment
3. PR approved and merged → Automated `terraform apply` runs
4. GitHub Actions assumes layer-specific IAM role (OIDC)
5. Deployment output logged in Actions console

**Example workflow**:
```yaml
name: Terraform Domains Layer

on:
  push:
    branches: [main]
    paths:
      - 'domains/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/domains-terraform-role
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: ./domains
        run: terraform init

      - name: Terraform Apply
        working-directory: ./domains
        run: terraform apply -auto-approve
```

---

## Testing Strategy

### Infrastructure Testing Levels

1. **Syntax validation**
   ```bash
   terraform fmt -check
   terraform validate
   ```

2. **Plan verification**
   ```bash
   terraform plan -out=tfplan
   # Review plan output before apply
   ```

3. **Integration testing** (manual)
   - Deploy to test AWS account or isolated state prefix
   - Verify resources created correctly
   - Test website accessibility, DNS resolution, HTTPS
   - Destroy after validation

4. **Automated testing** (future)
   - Pre-commit hooks for formatting/validation
   - Automated plan checks in CI/CD
   - Module testing with Terratest (if modules extracted)

---

## Troubleshooting Guide

### Common Issues

**Issue**: State locking timeout
- **Cause**: Previous Terraform run failed without releasing lock
- **Resolution**: `terraform force-unlock <LOCK_ID>`

**Issue**: Certificate validation stuck
- **Cause**: DNS records not propagated, validation record missing
- **Resolution**: Check Route53 records, wait for DNS propagation, re-apply

**Issue**: CloudFront 403 errors
- **Cause**: S3 bucket policy not allowing OAC access
- **Resolution**: Verify bucket policy includes CloudFront distribution ARN

**Issue**: Module not found
- **Cause**: Incorrect module source path
- **Resolution**: Verify path is `../modules/domain` or `../modules/static-site`

**Issue**: Role assumption failure
- **Cause**: IAM role doesn't exist, trust policy misconfigured
- **Resolution**: Check RBAC layer deployment, verify OIDC provider

---

## Repository Directory Structure

```
iac-aws/
├── .git/
├── .gitignore                      # Ignores *.tfstate, *.tfvars
├── README.md                       # Repository overview
├── architecture-overview.md        # This file
│
├── scp/                            # Layer 0: Service Control Policies
│   ├── CLAUDE.md                   # Layer context documentation
│   ├── main.tf                     # SCP resources
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf                 # Admin credentials initially
│   └── backend.tf                  # Commented (local state initially)
│
├── rbac/                           # Layer 1: IAM Roles
│   ├── CLAUDE.md
│   ├── main.tf                     # IAM roles, OIDC provider
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf                 # Admin credentials initially
│   └── backend.tf                  # Commented
│
├── tfstate-backend/                # Layer 2: State Backend
│   ├── CLAUDE.md
│   ├── main.tf                     # S3 bucket, DynamoDB table
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf                 # Assumes tfstate-backend-terraform-role
│   └── backend.tf                  # Commented (bootstrap problem)
│
├── domains/                        # Layer 3: Route53 + ACM
│   ├── CLAUDE.md
│   ├── main.tf                     # Calls domain module per domain
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf                 # Assumes domains-terraform-role
│   ├── backend.tf                  # Commented
│   └── terraform.tfvars            # Domain map (gitignored)
│
├── sites/                          # Layer 4: S3 + CloudFront + DNS
│   ├── CLAUDE.md
│   ├── main.tf                     # Calls static-site module per site
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf                 # Assumes sites-terraform-role
│   ├── backend.tf                  # Commented
│   └── terraform.tfvars            # Site map (gitignored)
│
└── modules/                        # Reusable modules
    ├── domain/                     # Route53 + ACM module
    │   ├── CLAUDE.md
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── versions.tf
    │
    └── static-site/                # S3 + CloudFront + DNS module
        ├── CLAUDE.md
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

---

## Future Roadmap

### Short-term Enhancements
- [ ] Create Terraform configurations for all layers (main.tf, variables.tf, etc.)
- [ ] Implement GitHub Actions CI/CD for automated deployments
- [ ] Add pre-commit hooks for Terraform formatting
- [ ] Set up billing alerts in AWS account

### Medium-term Enhancements
- [ ] Add CloudWatch alarms for error rates
- [ ] Implement CloudFront access logging
- [ ] Create staging environment (staging.domain.com)
- [ ] Add Lambda@Edge for advanced routing

### Long-term Enhancements
- [ ] Multi-region S3 state replication (disaster recovery)
- [ ] Terraform Cloud integration (centralized management)
- [ ] Separate AWS accounts for client work (multi-account strategy)
- [ ] Automated compliance scanning (AWS Config, Prowler)

---

## References

### Internal Documentation
- [scp/CLAUDE.md](./scp/CLAUDE.md) - SCP layer context
- [rbac/CLAUDE.md](./rbac/CLAUDE.md) - RBAC layer context
- [tfstate-backend/CLAUDE.md](./tfstate-backend/CLAUDE.md) - State backend layer context
- [domains/CLAUDE.md](./domains/CLAUDE.md) - Domains layer context
- [sites/CLAUDE.md](./sites/CLAUDE.md) - Sites layer context
- [modules/domain/CLAUDE.md](./modules/domain/CLAUDE.md) - Domain module documentation
- [modules/static-site/CLAUDE.md](./modules/static-site/CLAUDE.md) - Static site module documentation

### External Resources
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [CloudFront Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/best-practices.html)

---

**Document Version**: 2.0 (Single-Repository Architecture)
**Last Updated**: 2026-01-26
**Maintained By**: Noise2Signal LLC Infrastructure Team
