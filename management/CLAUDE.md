# Management Account - Overview

## Purpose

The **management account** (`noise2signal-llc-management`) is the root account of the AWS Organization. It serves as the governance, billing, and identity management hub for all accounts in the organization.

**Primary Responsibilities**:
- AWS Organizations management (create accounts, OUs, move accounts)
- Service Control Policies (organization-wide security guardrails)
- IAM Identity Center (AWS SSO for human users)
- Consolidated billing (organization payer account)
- Route53 domain registrations (domain ownership, NOT hosted zones)

**Design Principle**: Keep management account minimal - only governance, billing, and identity resources. All workloads (websites, applications) live in separate accounts.

---

## Account Details

**Account Name**: `noise2signal-llc-management`
**Account Email**: `aws-management@noise2signal.com` (or similar)
**Organizational Unit**: `Management OU`
**Cost Center Tag**: `infrastructure`

---

## Layer Structure

The management account has four layers, deployed in sequence:

```
management/
├── CLAUDE.md                       # This file
├── organization/                   # Layer 0: AWS Organizations
│   ├── CLAUDE.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── backend.tf (commented initially)
│
├── sso/                            # Layer 1: IAM Identity Center
│   ├── CLAUDE.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── backend.tf (commented initially)
│
├── scp/                            # Layer 2: Service Control Policies
│   ├── CLAUDE.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── backend.tf (commented initially)
│
└── tfstate-backend/                # Layer 3: Terraform State Backend
    ├── CLAUDE.md
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── provider.tf
    └── backend.tf (commented initially)
```

---

## Deployment Sequence

### Prerequisites
- AWS account created (becomes management account)
- Root user email and password
- AWS CLI installed and configured
- Terraform installed (v1.5+)

### Layer 0: Organization
**Purpose**: Enable AWS Organizations, create OUs, create whollyowned account

**Authentication**: Root user or admin IAM user
**State**: Local (initially)

**Key Actions**:
- Enable AWS Organizations
- Create OU structure (Management, Workloads, Clients, Sandbox)
- Create nested OU structure (Workloads/Production, Workloads/Development)
- Create `noise2signal-llc-whollyowned` account
- Configure consolidated billing

**Outputs**: Account IDs, OU IDs

**See**: [organization/CLAUDE.md](./organization/CLAUDE.md)

### Layer 1: SSO
**Purpose**: Configure IAM Identity Center for human user access

**Authentication**: Root user or admin IAM user
**State**: Local (initially)

**Key Actions**:
- Enable IAM Identity Center (in us-east-1)
- Create permission sets (AdministratorAccess, PowerUserAccess, ReadOnlyAccess)
- Create SSO user for boss (non-root admin)
- Assign permission sets to accounts (management, whollyowned)
- Configure MFA enforcement

**Outputs**: SSO instance ARN, permission set ARNs, user IDs

**See**: [sso/CLAUDE.md](./sso/CLAUDE.md)

### Layer 2: SCP
**Purpose**: Apply service control policies to OUs

**Authentication**: Root user, admin IAM user, or SSO admin
**State**: Local (initially)

**Key Actions**:
- Create SCP for Management OU (minimal restrictions)
- Create SCP for Workloads OU (restrictive, service allow-list)
- Create SCP for Clients OU (similar to Workloads)
- Attach SCPs to OUs (not individual accounts)

**Outputs**: SCP IDs, attachment IDs

**See**: [scp/CLAUDE.md](./scp/CLAUDE.md)

### Layer 3: Tfstate Backend (Optional, Last)
**Purpose**: Create S3 + DynamoDB backend for management account state

**Authentication**: SSO admin or IAM role
**State**: Local → Remote (migrates after creation)

**Key Actions**:
- Create S3 bucket (`n2s-terraform-state-management`)
- Enable versioning, encryption, lifecycle policies
- Create DynamoDB table for state locking
- Migrate all management layers to remote state

**Outputs**: Bucket name, DynamoDB table name

**See**: [tfstate-backend/CLAUDE.md](./tfstate-backend/CLAUDE.md)

---

## Service Control Policies (Applied to This Account)

The management account lives in the **Management OU**, which has **minimal SCPs**:

**Allowed**:
- All IAM, STS, IAM Identity Center operations
- AWS Organizations (full access)
- S3, DynamoDB (for state backend)
- Route53 Domains (domain registration only)
- CloudWatch, CloudTrail (monitoring, auditing)

**Denied**:
- Destructive organization actions (delete org, leave org)
- Root user actions (future: force SSO for all human access)

**Rationale**: Management account needs broad permissions to govern the organization, but should deny destructive actions that could break the organization structure.

---

## IAM Roles

### Initial Bootstrap
**No IAM roles needed initially** - use root user or admin IAM user for bootstrap.

### After SSO Configuration
**Human Access**: Use AWS SSO (IAM Identity Center) exclusively:
- Boss SSO user → AdministratorAccess permission set → All accounts
- Future team members → PowerUserAccess or ReadOnlyAccess

### Future: Terraform Execution Roles
If GitHub Actions needs to deploy management account infrastructure:
- `organization-terraform-role`: Manage AWS Organizations
- `sso-terraform-role`: Manage IAM Identity Center
- `scp-terraform-role`: Manage SCPs
- `tfstate-terraform-role`: Manage state backend

Each role would trust GitHub OIDC provider (created in this account).

**Current State**: Not implemented (manual deployment via SSO sufficient for now)

---

## Terraform State

### Initial State (Local)
All layers start with local state files:
```
management/
├── organization/terraform.tfstate
├── sso/terraform.tfstate
├── scp/terraform.tfstate
└── tfstate-backend/terraform.tfstate
```

**Important**: Add `*.tfstate` to `.gitignore` - never commit state files!

### Remote State (After Layer 3)
After deploying `tfstate-backend` layer, migrate all layers to S3:

```
s3://n2s-terraform-state-management/
└── management/
    ├── organization.tfstate
    ├── sso.tfstate
    ├── scp.tfstate
    └── tfstate-backend.tfstate
```

**Migration Steps**:
1. Deploy `tfstate-backend` layer (creates S3 + DynamoDB)
2. Uncomment `backend.tf` in each layer
3. Run `terraform init -migrate-state` in each layer
4. Verify state in S3: `aws s3 ls s3://n2s-terraform-state-management/management/`
5. Delete local state files: `rm terraform.tfstate*`

---

## Cost Allocation

All resources in the management account use these tags:

```hcl
tags = {
  Organization = "noise2signal-llc"
  Account      = "management"
  CostCenter   = "infrastructure"
  Environment  = "production"
  ManagedBy    = "terraform"
  Layer        = "organization"  # or "sso", "scp", "tfstate-backend"
}
```

**Cost Center**: `infrastructure` (organization-level overhead)

**Monthly Cost Estimate**:
```
AWS Organizations:           Free
IAM Identity Center:         Free
Service Control Policies:    Free
Route53 domain registration: ~$12/year (~$1/month per domain)
S3 state backend:            ~$0.10
DynamoDB state locking:      ~$0.25
──────────────────────────────
Total:                       ~$1.35/month (assuming 1 domain)
```

---

## Security Best Practices

### Root User
- **Use only for**:
  - Initial organization setup (Layer 0-1)
  - Break-glass emergency access (when SSO is down)
  - Billing/payment method changes
- **Secure root user**:
  - Enable MFA (hardware token recommended)
  - Use strong, unique password (password manager)
  - Store credentials securely (offline, encrypted)
  - Do NOT use root for day-to-day operations

### SSO (IAM Identity Center)
- **Use for all human access** after Layer 1 is deployed
- **Enforce MFA** for all SSO users
- **Principle of least privilege**: Assign minimal permission sets needed
- **Regular audits**: Review SSO user access quarterly

### Service Control Policies
- **Test SCPs in sandbox** before applying to production OUs
- **Avoid locking yourself out**: Keep Management OU SCPs minimal
- **Document all SCPs**: Explain intent and rationale
- **Version control**: All SCP changes go through Terraform

### Terraform State
- **Never commit state files** to Git (`.gitignore`)
- **Encrypt state at rest** (S3 server-side encryption)
- **Enable versioning** (recover from accidental deletions)
- **Restrict access** (only Terraform execution roles can read/write)

---

## Cross-Account Dependencies

### Outbound (Management → Other Accounts)
- **Organization membership**: Management account creates and owns all member accounts
- **SCPs**: Management account applies SCPs to OUs (affects all member accounts)
- **SSO access**: Management account grants SSO users access to member accounts

### Inbound (Other Accounts → Management)
- **Route53 domain registrations**: Whollyowned account hosted zones need NS records updated in management account domain registrations
  - **Resolution**: Manual update (Phase 3 of bootstrap process)
  - **Future**: Automate with Lambda or Terraform data sources

---

## Disaster Recovery

### Organization Recovery
- **Organization cannot be deleted** if it has member accounts (protection)
- **If organization is disabled**: Re-enable via root user + AWS Support
- **If root user is lost**: AWS Support (identity verification required)

### State File Recovery
- **S3 versioning enabled**: Recover previous state versions
- **Lifecycle policy**: Retain old versions for 90 days
- **Local backups**: Keep local `.tfstate.backup` files until migration complete

### SSO Recovery
- **If SSO is misconfigured**: Use root user to fix
- **If SSO user is locked out**: Root user can reset/recreate
- **Break-glass**: Root user is always available as fallback

---

## Troubleshooting

### Cannot Create Organization
- **Cause**: Account already in another organization, or organization already exists
- **Resolution**: Check `aws organizations describe-organization`, leave existing org if needed

### Cannot Create Member Account
- **Cause**: Email already in use, organization limit reached (default 10 accounts)
- **Resolution**: Use unique email, or request limit increase via AWS Support

### SSO Not Available in Region
- **Cause**: IAM Identity Center only available in certain regions
- **Resolution**: Deploy SSO in `us-east-1` (recommended for global services)

### SCP Blocks Legitimate Action
- **Cause**: SCP too restrictive, applied to wrong OU
- **Resolution**: Review SCP, test in isolation, adjust and re-apply

### Cannot Migrate to Remote State
- **Cause**: S3 bucket doesn't exist, DynamoDB table missing, IAM permissions insufficient
- **Resolution**: Verify `tfstate-backend` layer deployed successfully, check IAM permissions

---

## Next Steps

After deploying the management account:

1. **Verify organization structure**:
   ```bash
   aws organizations describe-organization
   aws organizations list-accounts
   aws organizations list-organizational-units-for-parent --parent-id r-xxxx
   ```

2. **Log in with SSO**:
   ```bash
   aws configure sso --profile management-admin
   aws sso login --profile management-admin
   ```

3. **Proceed to whollyowned account**: See [../whollyowned/CLAUDE.md](../whollyowned/CLAUDE.md)

---

## References

### Layer Documentation
- [organization/CLAUDE.md](./organization/CLAUDE.md)
- [sso/CLAUDE.md](./sso/CLAUDE.md)
- [scp/CLAUDE.md](./scp/CLAUDE.md)
- [tfstate-backend/CLAUDE.md](./tfstate-backend/CLAUDE.md)

### Parent Documentation
- [../CLAUDE.md](../CLAUDE.md) - Overall architecture

### AWS Documentation
- [AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)

---

**Last Updated**: 2026-01-26
**Account**: noise2signal-llc-management
**Maintainer**: Noise2Signal LLC Infrastructure Team
