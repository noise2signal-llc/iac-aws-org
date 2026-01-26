# Noise2Signal LLC - AWS Infrastructure as Code

Infrastructure as Code (IaC) repository for Noise2Signal LLC's AWS environment using Terraform and AWS Organizations.

## Architecture Overview

This repository manages a **multi-account AWS Organization** for secure, scalable infrastructure:

- **Management Account**: Governance, billing, IAM Identity Center (SSO), Service Control Policies
- **Whollyowned Account**: Production websites for Noise2Signal LLC brands
- **Future**: Separate accounts for client commissioned work

### Key Features

✅ **Multi-Account Isolation**: Separate accounts for governance and workloads
✅ **AWS Organizations**: Centralized management with organizational units (OUs)
✅ **Service Control Policies**: Organization-level security guardrails
✅ **IAM Identity Center**: Centralized SSO for human access across accounts
✅ **Per-Account State Backends**: Isolated Terraform state for blast radius control
✅ **Infrastructure Layers**: Modular, ordered deployment of infrastructure components
✅ **Cost Allocation**: Detailed tagging for cost tracking and chargeback

---

## Repository Structure

```
iac-aws/
├── CLAUDE.md                       # Comprehensive architecture documentation
├── MIGRATION.md                    # Migration guide (single→multi-account)
├── README.md                       # This file
│
├── management/                     # Management Account
│   ├── CLAUDE.md                   # Account overview
│   ├── organization/               # Layer 0: AWS Org, OUs, accounts
│   ├── sso/                        # Layer 1: IAM Identity Center
│   ├── scp/                        # Layer 2: Service Control Policies
│   └── tfstate-backend/            # Layer 3: State backend (optional)
│
├── whollyowned/                    # Whollyowned Production Account
│   ├── CLAUDE.md                   # Account overview
│   ├── rbac/                       # Layer 0: IAM roles + OIDC
│   ├── tfstate-backend/            # Layer 1: State backend (optional)
│   ├── domains/                    # Layer 2: Route53 zones + ACM
│   └── sites/                      # Layer 3: S3 + CloudFront + DNS
│
└── modules/                        # Shared Terraform modules
    ├── domain/                     # Route53 zone + ACM certificate
    └── static-site/                # S3 + CloudFront + DNS pattern
```

---

## Quick Start

### Prerequisites

- **AWS Account**: Your first AWS account (becomes management account)
- **Terraform**: v1.5+ installed ([Download](https://www.terraform.io/downloads))
- **AWS CLI**: v2.x installed ([Download](https://aws.amazon.com/cli/))
- **Git**: For version control

### Initial Setup (Greenfield Deployment)

#### Phase 1: Deploy Management Account

```bash
# 1. Clone repository
git clone https://github.com/noise2signal/iac-aws.git
cd iac-aws

# 2. Configure AWS CLI with management account credentials
aws configure --profile management-admin

# 3. Deploy organization layer (creates AWS Org + whollyowned account)
cd management/organization
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
terraform init
terraform apply

# 4. Deploy SSO layer (IAM Identity Center for human access)
cd ../sso
# Create SSO user manually in AWS console first (one-time)
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

# 5. Deploy SCP layer (Service Control Policies for security)
cd ../scp
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

# 6. (Optional) Deploy state backend and migrate to remote state
cd ../tfstate-backend
terraform init
terraform apply
# Then migrate all management layers to S3
```

#### Phase 2: Deploy Whollyowned Account

```bash
# 1. Access whollyowned account via SSO
aws sso login --profile whollyowned-admin

# 2. Deploy RBAC layer (IAM roles for Terraform)
cd whollyowned/rbac
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

# 3. (Optional) Deploy state backend
cd ../tfstate-backend
terraform init
terraform apply
# Migrate whollyowned layers to S3

# 4. Deploy domains layer (Route53 zones + ACM certificates)
cd ../domains
cp terraform.tfvars.example terraform.tfvars
# Add your domains to terraform.tfvars
terraform init
terraform apply
# Wait 5-10 minutes for ACM certificate validation

# 5. Deploy sites layer (S3 + CloudFront + DNS records)
cd ../sites
cp terraform.tfvars.example terraform.tfvars
# Add your sites to terraform.tfvars
terraform init
terraform apply
# Wait 15-30 minutes for CloudFront distribution deployment

# 6. Upload website content
aws s3 sync ./your-website/ s3://yourdomain.com/ --delete
aws cloudfront create-invalidation --distribution-id <DIST_ID> --paths "/*"
```

#### Phase 3: Cross-Account Wiring

```bash
# Update domain nameservers (manual step)
# See CLAUDE.md for detailed instructions

# 1. Get NS records from whollyowned hosted zone
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --profile whollyowned-admin \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value"

# 2. Update domain registration in management account
aws route53domains update-domain-nameservers \
  --region us-east-1 \
  --profile management-admin \
  --domain-name yourdomain.com \
  --nameservers Name=ns-xxx.awsdns-xx.com Name=ns-xxx.awsdns-xx.net ...
```

---

## Documentation

### Primary Documentation

- **[CLAUDE.md](./CLAUDE.md)** - Comprehensive architecture guide (START HERE)
- **[MIGRATION.md](./MIGRATION.md)** - Migration guide for existing single-account infrastructure

### Account-Level Documentation

- **[management/CLAUDE.md](./management/CLAUDE.md)** - Management account overview
- **[whollyowned/CLAUDE.md](./whollyowned/CLAUDE.md)** - Whollyowned account overview

### Layer-Level Documentation

Each layer has a `CLAUDE.md` file with detailed deployment instructions:

**Management Account Layers**:
- [organization/CLAUDE.md](./management/organization/CLAUDE.md) - AWS Organizations, OUs, accounts
- [sso/CLAUDE.md](./management/sso/CLAUDE.md) - IAM Identity Center (AWS SSO)
- [scp/CLAUDE.md](./management/scp/CLAUDE.md) - Service Control Policies
- [tfstate-backend/CLAUDE.md](./management/tfstate-backend/CLAUDE.md) - State backend

**Whollyowned Account Layers**:
- [rbac/CLAUDE.md](./whollyowned/rbac/CLAUDE.md) - IAM roles + GitHub OIDC
- [tfstate-backend/CLAUDE.md](./whollyowned/tfstate-backend/CLAUDE.md) - State backend
- [domains/CLAUDE.md](./whollyowned/domains/CLAUDE.md) - Route53 zones + ACM
- [sites/CLAUDE.md](./whollyowned/sites/CLAUDE.md) - S3 + CloudFront + DNS

**Module Documentation**:
- [modules/domain/CLAUDE.md](./modules/domain/CLAUDE.md) - Domain module
- [modules/static-site/CLAUDE.md](./modules/static-site/CLAUDE.md) - Static site module

---

## AWS Organization Structure

```
noise2signal-llc (Organization Root)
├── Management OU
│   └── noise2signal-llc-management
│       • AWS Organizations, SCPs
│       • IAM Identity Center (SSO)
│       • Consolidated billing
│       • Route53 domain registrations
│
├── Workloads OU
│   ├── Production OU
│   │   └── noise2signal-llc-whollyowned
│   │       • Route53 hosted zones
│   │       • ACM certificates
│   │       • S3, CloudFront (websites)
│   │
│   └── Development OU (future: staging accounts)
│
├── Clients OU (future: commissioned work)
│   ├── noise2signal-llc-client-acme
│   └── noise2signal-llc-client-beta
│
└── Sandbox OU (future: experimentation)
```

---

## State Management

### State Backend Strategy

Each account has its own S3 state backend for isolation:

**Management Account**:
```
s3://n2s-terraform-state-management/
└── management/
    ├── organization.tfstate
    ├── sso.tfstate
    ├── scp.tfstate
    └── tfstate-backend.tfstate
```

**Whollyowned Account**:
```
s3://n2s-terraform-state-whollyowned/
└── whollyowned/
    ├── rbac.tfstate
    ├── tfstate-backend.tfstate
    ├── domains.tfstate
    └── sites.tfstate
```

**Why Per-Account Backends?**
- **Blast radius control**: Issues in one account don't affect others
- **Access control**: Each account's state is isolated
- **Account ownership**: Easy to transfer account with its state

### Initial State (Local)

All layers start with **local state files** (`.tfstate` in each directory, gitignored).

After deploying the `tfstate-backend` layer in each account:
1. Uncomment `backend.tf` in each layer
2. Run `terraform init -migrate-state`
3. Verify state in S3
4. Delete local state files

---

## Security

### Service Control Policies (SCPs)

SCPs constrain all accounts in each OU:

**Management OU**: Minimal restrictions (governance needs broad access)
- Allow: All services needed for governance (IAM, Organizations, SSO, S3, DynamoDB)
- Deny: Destructive organization actions (delete org, leave org)

**Workloads OU**: Restrictive service allow-list
- Allow: IAM, STS, S3, DynamoDB, Route53, ACM, CloudFront, CloudWatch
- Deny: All other AWS services (EC2, RDS, Lambda, etc. unless explicitly added)
- Deny: Operations outside us-east-1 (except global services)
- Deny: Root user actions (force IAM roles/SSO)

**Clients OU**: Same as Workloads OU (with potential client-specific restrictions)

### IAM Identity Center (AWS SSO)

**Human Access**: All human users access AWS via SSO (no long-lived IAM user credentials)

**Permission Sets**:
- **AdministratorAccess**: Boss only (full admin)
- **PowerUserAccess**: Developers (no IAM/Org permissions)
- **ReadOnlyAccess**: Auditors, finance team

**MFA**: Enforced for all users

### IAM Roles (Per Account)

**Whollyowned Account**:
- `rbac-terraform-role`: Bootstrap role (creates other roles)
- `tfstate-terraform-role`: State backend management
- `domains-terraform-role`: Route53 + ACM management
- `sites-terraform-role`: S3 + CloudFront management

**GitHub OIDC**: Each account has its own OIDC provider for CI/CD (future)

### Encryption

- **At Rest**: S3 (AES256), DynamoDB (AWS-managed keys)
- **In Transit**: HTTPS enforced, TLS 1.2+ minimum
- **State Files**: Encrypted in S3, versioned (90-day retention)

---

## Cost Estimates

### Monthly Costs (Per Account)

**Management Account** (~$1.35/month):
```
AWS Organizations:           Free
IAM Identity Center:         Free
Service Control Policies:    Free
Route53 domain registration: ~$12/year ($1/month per domain)
S3 state backend:            ~$0.10
DynamoDB state locking:      ~$0.25
```

**Whollyowned Account** (~$1.87-5.87/month per site):
```
S3 state backend:            ~$0.10
DynamoDB state locking:      ~$0.25
Route53 hosted zone:         ~$0.50
ACM certificate:             Free (with CloudFront)
S3 website storage:          ~$0.02/GB
CloudFront:                  ~$1-5 (traffic-dependent)
```

**Total Organization** (1 domain, 1 site): ~$3-7/month

**Scaling**: Each additional site adds ~$1.87-5.87/month

---

## Adding a New Website

### Step 1: Add Domain to domains layer

```hcl
# whollyowned/domains/terraform.tfvars
domains = {
  "existingdomain.com" = { ... },
  "newdomain.com" = { ... },  # Added
}
```

```bash
cd whollyowned/domains
terraform apply
# Wait for ACM certificate validation (5-10 min)
```

### Step 2: Add Site to sites layer

```hcl
# whollyowned/sites/terraform.tfvars
sites = {
  "existingdomain.com" = { ... },
  "newdomain.com" = { ... },  # Added
}
```

```bash
cd ../sites
terraform apply
# Wait for CloudFront deployment (15-30 min)
```

### Step 3: Upload Content

```bash
aws s3 sync ./new-site/ s3://newdomain.com/ --delete
aws cloudfront create-invalidation --distribution-id <DIST_ID> --paths "/*"
```

### Step 4: Update Domain NS Records

Follow Phase 3 instructions to update domain nameservers.

**Total Time**: ~45 minutes

---

## Development Workflow

### Local Development

```bash
# 1. Clone repository
git clone https://github.com/noise2signal/iac-aws.git
cd iac-aws

# 2. Checkout feature branch
git checkout -b feature/add-new-site

# 3. Make changes to Terraform files
cd whollyowned/sites
# Edit main.tf, variables.tf, etc.

# 4. Plan changes
terraform plan

# 5. Apply (testing only - production changes should go through PR)
terraform apply

# 6. Commit changes
git add .
git commit -m "Add new website for newdomain.com"
git push origin feature/add-new-site

# 7. Open pull request on GitHub
```

### CI/CD (Future Enhancement)

**Current**: Terraform runs locally (manual deployment)

**Future**: GitHub Actions workflows for automated plan/apply
- PR opened → `terraform plan` runs, posts comment
- PR merged → `terraform apply` runs automatically
- Uses GitHub OIDC for authentication (no long-lived credentials)

---

## Troubleshooting

### Common Issues

**Cannot access whollyowned account**
- **Cause**: SSO not configured or permission set not assigned
- **Fix**: Check IAM Identity Center, assign AdministratorAccess to your user

**SCP blocks legitimate action**
- **Cause**: Service not allowed in Workloads OU SCP
- **Fix**: Add service to SCP in `management/scp/main.tf`, apply changes

**ACM certificate validation stuck**
- **Cause**: DNS records not propagated, or NS records not updated
- **Fix**: Verify hosted zone has DNS validation records, wait 5-10 minutes

**CloudFront 403 errors**
- **Cause**: S3 bucket policy doesn't allow CloudFront OAC access
- **Fix**: Verify bucket policy in sites layer, re-apply if needed

**Terraform state locking timeout**
- **Cause**: Previous Terraform run failed without releasing lock
- **Fix**: `terraform force-unlock <LOCK_ID>`

See layer-specific `CLAUDE.md` files for more detailed troubleshooting.

---

## Contributing

### Git Workflow

1. **Branch naming**: `feature/<description>`, `fix/<description>`, `docs/<description>`
2. **Commits**: Clear, descriptive commit messages
3. **Pull Requests**: Required for all changes to `main` branch
4. **Reviews**: At least one approval required before merge

### Terraform Standards

- **Formatting**: Run `terraform fmt` before committing
- **Validation**: Run `terraform validate` before committing
- **Planning**: Always review `terraform plan` output before applying
- **State**: Never commit `.tfstate` files (gitignored)
- **Secrets**: Never commit credentials, API keys, or sensitive data

---

## Support & Contact

**Questions?** See comprehensive documentation in [CLAUDE.md](./CLAUDE.md)

**Migrations?** See migration guide in [MIGRATION.md](./MIGRATION.md)

**Issues?** Open an issue on GitHub or contact the infrastructure team

---

## License

Copyright © 2026 Noise2Signal LLC. All rights reserved.

This repository contains proprietary infrastructure code for Noise2Signal LLC's AWS environment.

---

## References

- [AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

---

**Repository Version**: 3.0 (Multi-Account Architecture)
**Last Updated**: 2026-01-26
**Maintained By**: Noise2Signal LLC Infrastructure Team
