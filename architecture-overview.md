# Noise2Signal LLC - Terraform Multi-Repo Architecture

## Executive Summary

This document provides a comprehensive overview of the Terraform infrastructure architecture for Noise2Signal LLC's AWS account. The design separates concerns across multiple repositories, enabling modular development, clear ownership boundaries, and scalable management of wholly-owned and commissioned website infrastructure.

**Key Design Principles:**
- **Separation of Concerns**: Infrastructure layers isolated into discrete repositories
- **Reusability**: Shared patterns extracted into versioned modules
- **Security**: Fine-grained IAM permissions, encryption by default
- **Scalability**: Variable-driven multi-site deployment within repos
- **Client IP Separation**: Clear boundaries between Noise2Signal and client-owned properties

---

## Repository Architecture

### Three-Tier Infrastructure Repos

```
┌─────────────────────────────────────────────────────────────┐
│  Tier 1: terraform-inception                                │
│  Purpose: Terraform harness (bootstrap infrastructure)      │
│  ─────────────────────────────────────────────────────────  │
│  • S3 state backend                                         │
│  • DynamoDB state locking                                   │
│  • GitHub Actions IAM role (OIDC)                           │
│  • Developer Terraform IAM role                             │
│                                                             │
│  Deployed First: Manual bootstrap, then remote state        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Tier 2: terraform-dns-domains                              │
│  Purpose: Domain ownership layer                            │
│  ─────────────────────────────────────────────────────────  │
│  • Route53 hosted zones (5 domains)                         │
│  • ACM certificates (us-east-1, DNS validation)             │
│  • CAA records (optional)                                   │
│                                                             │
│  Deployed Second: After domains transferred to Route53      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Tier 3: terraform-static-sites                             │
│  Purpose: Website infrastructure (wholly-owned sites)       │
│  ─────────────────────────────────────────────────────────  │
│  • S3 buckets (primary + www redirect)                      │
│  • CloudFront distributions (CDN)                           │
│  • Route53 A/AAAA records (→ CloudFront)                    │
│  • Complete isolation per site                              │
│                                                             │
│  Deployed Third: After zones/certs exist                    │
└─────────────────────────────────────────────────────────────┘
```

### Module Repositories (Reusable Components)

```
┌──────────────────────────────────────────┐
│  terraform-aws-module-cdn                │
│  CloudFront distribution patterns        │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  terraform-aws-module-storage            │
│  S3 bucket patterns for static sites     │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  terraform-aws-module-acm                │
│  ACM certificate management              │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  terraform-aws-module-route53-records    │
│  DNS alias record patterns               │
└──────────────────────────────────────────┘

Consumed by: terraform-static-sites, terraform-dns-domains
Source method: Git URL with version tags
```

---

## State Management

### Remote State Backend (Shared)

All infrastructure repos use a shared S3 backend:

```
s3://noise2signal-terraform-state/
├── noise2signal/                    # Wholly-owned infrastructure
│   ├── inception.tfstate
│   ├── dns-domains.tfstate
│   └── static-sites.tfstate
│
└── client-<name>/                   # Future: commissioned work
    ├── dns-domains.tfstate
    └── static-sites.tfstate
```

**State Locking**: DynamoDB table `noise2signal-terraform-state-lock`

**Encryption**: AES256 server-side encryption (all state files)

**Access Control**: Restricted to Terraform execution IAM roles only

---

## Cross-Repository Dependencies

### Dependency Resolution Pattern (Interim)

**Current approach**: Data sources with naming conventions

```hcl
# In terraform-static-sites
# Discovers hosted zone from terraform-dns-domains
data "aws_route53_zone" "site" {
  name = var.domain_name
}

# Discovers ACM certificate from terraform-dns-domains
data "aws_acm_certificate" "site" {
  provider    = aws.us_east_1
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
```

**Future approach**: Remote state data sources

```hcl
# Future pattern (not yet implemented)
data "terraform_remote_state" "dns_domains" {
  backend = "s3"
  config = {
    bucket = "noise2signal-terraform-state"
    key    = "noise2signal/dns-domains.tfstate"
    region = "us-east-1"
  }
}

# Usage:
# data.terraform_remote_state.dns_domains.outputs.hosted_zone_ids["camden-wander.com"]
```

**Design rationale**: Data sources are easier to swap out than tight state coupling. Start simple, evolve to remote state when needed.

---

## Deployment Workflow

### Initial Infrastructure Bootstrap

**Step 1: Deploy inception repo**
```bash
cd terraform-inception
terraform init                  # Local state initially
terraform apply
# Migrate to remote state after S3/DynamoDB created
```

**Step 2: Deploy dns-domains repo**
```bash
cd terraform-dns-domains
terraform init                  # Uses S3 backend from inception
terraform apply
# Wait for ACM certificate validation (5-10 minutes)
```

**Step 3: Deploy static-sites repo**
```bash
cd terraform-static-sites
terraform init
terraform apply
# Wait for CloudFront deployment (15-30 minutes)
```

**Step 4: Upload website content**
```bash
aws s3 sync ./website/ s3://camden-wander.com/ --delete
aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"
```

### Adding a New Site

**Prerequisites:**
- Domain transferred to Route53 or ready for new zone

**Process:**
1. **Add to dns-domains repo**
   ```hcl
   # terraform.tfvars
   domains = [
     "camden-wander.com",
     "new-domain.com",  # Added
   ]
   ```
   Apply changes, wait for certificate validation.

2. **Add to static-sites repo**
   ```hcl
   # terraform.tfvars
   sites = [
     {
       domain       = "camden-wander.com"
       project_name = "camden-wander-site"
     },
     {
       domain       = "new-domain.com"
       project_name = "new-site"
     },
   ]
   ```
   Apply changes, wait for CloudFront deployment.

3. **Upload content**
   ```bash
   aws s3 sync ./new-site/ s3://new-domain.com/
   ```

**Timeline**: ~45 minutes (certificate validation + CloudFront deployment)

---

## IAM Roles and Permissions

### GitHub Actions Role (Fine-Grained)

**Trust policy**: GitHub OIDC provider (repos: `noise2signal/*`)

**Permissions** (scoped to known operations):
- S3: State bucket access (Get/Put objects with prefix restrictions)
- DynamoDB: State locking (GetItem, PutItem, DeleteItem)
- Route53: Zone/record management (specific zones only)
- ACM: Certificate request/validation (us-east-1 only)
- CloudFront: Distribution management
- S3: Website bucket creation/management (restricted to website bucket naming pattern)

**Session duration**: 1 hour

**Usage**: GitHub Actions workflows for automated deployments

### Developer Terraform Role (Expanded)

**Trust policy**: AWS SSO principal or specific IAM users

**Permissions** (broader for exploration):
- All GitHub Actions permissions, PLUS:
- IAM: CreateRole, AttachRolePolicy (for prototyping)
- CloudWatch: CreateLogGroup, PutMetricAlarm
- Additional services as needed (scoped to account)

**Session duration**: 12 hours

**Usage**: Human developers iterating on infrastructure

---

## Security Architecture

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
- **CAA records**: Restrict certificate issuance to AWS only (optional)
- **Registrar lock**: Enabled (prevents unauthorized transfers)
- **DNSSEC**: Optional (can be enabled for enhanced security)

---

## Cost Structure

### Infrastructure Costs (Monthly Estimates)

**Tier 1: Inception (One-time setup)**
- S3 state bucket: ~$0.10
- DynamoDB state locking: ~$0.25
- IAM roles: Free
- **Total**: ~$0.35/month

**Tier 2: DNS Domains (Per domain)**
- Route53 hosted zone: $0.50
- Route53 queries: ~$0.40 per 1M queries
- ACM certificates: Free (when used with CloudFront)
- **Total per domain**: ~$0.90/month + query costs

**Tier 3: Static Sites (Per site)**
- S3 storage: ~$0.023/GB
- S3 requests: ~$0.005 per 1K requests
- CloudFront data transfer: ~$0.085/GB (PriceClass_100)
- CloudFront requests: ~$0.0075 per 10K HTTPS requests
- **Total per site**: $1-5/month (varies by traffic)

**Total for 5 Wholly-Owned Sites**:
```
Inception:    $0.35
DNS (5 sites): $4.50 + queries
Sites (5):    $5-25 (traffic-dependent)
─────────────────────────
Total:        ~$10-30/month
```

### Cost Optimization
- CloudFront PriceClass_100 (US/Canada/Europe only)
- S3 lifecycle policies for old versions
- Route53 query monitoring for anomalies
- Billing alerts at $5, $20, $50 thresholds

---

## Multi-Tenancy Strategy

### Wholly-Owned vs. Commissioned Work

**Repository separation at GitHub level:**

```
Wholly-Owned (Noise2Signal IP):
- terraform-static-sites
  → Manages: camden-wander.com, domain2.com, etc.
  → State: s3://.../noise2signal/static-sites.tfstate

Commissioned (Client IP):
- terraform-static-sites-client-acme
  → Manages: client-acme.com, etc.
  → State: s3://.../client-acme/static-sites.tfstate
  → Separate repo = separate access control
```

**Design principle**: Each client's infrastructure is a **separate GitHub repository** (cloned from wholly-owned pattern) with:
- Separate state file (isolation, blast radius control)
- Separate access controls (client sees only their config)
- Separate tagging for billing/ownership tracking

**Future consideration**: Client work may move to separate AWS accounts (cross-account infrastructure)

---

## Disaster Recovery

### State File Recovery
- **S3 versioning**: Enabled (recover from accidental deletions)
- **Lifecycle policy**: Retain old versions for 90 days
- **Backup strategy**: S3 bucket replication to secondary region (future enhancement)

### Infrastructure Recovery
All infrastructure is defined as code:
1. State files backed up in versioned S3 bucket
2. Terraform code in Git (version controlled)
3. Recovery: `terraform plan` + `terraform apply` (idempotent)

### Certificate Recovery
- ACM handles automatic renewal (60 days before expiration)
- If renewal fails, ACM sends email alerts
- Manual re-validation possible via Route53 DNS records

---

## Monitoring and Observability

### Current Monitoring
- **AWS Cost Explorer**: Monthly cost tracking
- **Billing alerts**: $5, $20, $50 thresholds
- **CloudFront metrics**: 4xx/5xx error rates (CloudWatch)
- **Route53 health checks**: Optional (consider cost vs. benefit)

### Future Enhancements
- CloudWatch alarms for error rate spikes
- CloudFront access logging (to S3 bucket)
- Automated drift detection (compare state vs. live resources)
- Terraform Cloud for centralized state/run management

---

## Development Workflow

### Local Development
1. Clone infrastructure repo
2. Assume developer IAM role (AWS SSO or CLI)
3. Make changes to `.tf` files
4. Run `terraform plan` to preview changes
5. Run `terraform apply` to deploy (dev/testing only)
6. Commit changes to feature branch
7. Open pull request for review

### CI/CD (GitHub Actions)
1. PR opened → Automated `terraform plan` runs
2. Plan output posted as PR comment
3. PR approved and merged → Automated `terraform apply` runs
4. GitHub Actions assumes fine-grained IAM role (OIDC)
5. Deployment output logged in Actions console

**Example workflow**:
```yaml
name: Terraform Apply

on:
  push:
    branches: [main]

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
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Terraform Init
        run: terraform init

      - name: Terraform Apply
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
   - Deploy to test AWS account or isolated state
   - Verify resources created correctly
   - Test website accessibility, DNS resolution, HTTPS
   - Destroy after validation

4. **Automated testing** (future)
   - Terratest for module validation
   - Pre-commit hooks for formatting/validation
   - Automated plan checks in CI/CD

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
- **Cause**: Git URL incorrect, version tag missing, private repo auth
- **Resolution**: Verify tag exists, configure Git credentials if private

---

## Future Roadmap

### Short-term Enhancements
- [ ] Create first 3 module repos (cdn, storage, acm)
- [ ] Implement GitHub Actions CI/CD for automated deployments
- [ ] Add pre-commit hooks for Terraform formatting
- [ ] Set up billing alerts in AWS account

### Medium-term Enhancements
- [ ] Migrate data sources to remote state lookups
- [ ] Add CloudWatch alarms for error rates
- [ ] Implement CloudFront access logging
- [ ] Create staging environment (staging.domain.com)
- [ ] Add Lambda@Edge for advanced routing

### Long-term Enhancements
- [ ] Private Terraform registry (eliminate Git URL complexity)
- [ ] Multi-region S3 state replication (disaster recovery)
- [ ] Terraform Cloud integration (centralized management)
- [ ] Separate AWS accounts for client work (multi-account strategy)
- [ ] Automated compliance scanning (AWS Config, Prowler)

---

## References

### Internal Documentation
- [inception-CLAUDE.md](./inception-CLAUDE.md) - Inception repo context
- [dns-domains-CLAUDE.md](./dns-domains-CLAUDE.md) - DNS domains repo context
- [static-sites-CLAUDE.md](./static-sites-CLAUDE.md) - Static sites repo context
- [modules-CLAUDE.md](./modules-CLAUDE.md) - Module development standards
- [CLAUDE.md](./CLAUDE.md) - Primary AWS account context

### External Resources
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [CloudFront Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/best-practices.html)

---

## Appendix: Quick Command Reference

### State Management
```bash
# Initialize with remote state
terraform init

# Migrate local state to remote
terraform init -migrate-state

# Force unlock stuck state
terraform force-unlock <LOCK_ID>
```

### Deployment
```bash
# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Destroy resources
terraform destroy
```

### Content Management
```bash
# Upload website content
aws s3 sync ./website/ s3://domain.com/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id <ID> \
  --paths "/*"
```

### Verification
```bash
# Check certificate validation
aws acm describe-certificate --certificate-arn <ARN> --region us-east-1

# Test DNS resolution
dig domain.com A +short
dig domain.com AAAA +short

# Test HTTPS
curl -I https://domain.com

# Check security headers
curl -I https://domain.com | grep -i "strict-transport-security"
```

---

**Document Version**: 1.0
**Last Updated**: 2024-03-15
**Maintained By**: Noise2Signal LLC Infrastructure Team
