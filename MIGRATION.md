# Migration Guide: Single-Account to Multi-Account Architecture

## Overview

This guide helps migrate from the original single-account Terraform architecture to the new multi-account AWS Organizations architecture.

**Original Architecture**:
- Single AWS account with layered infrastructure (scp → rbac → tfstate-backend → domains → sites)
- All resources in one account

**New Architecture**:
- AWS Organizations with multiple accounts
- Management account: Governance, SSO, billing, domain registrations
- Whollyowned account: Production websites, Route53 zones, ACM, S3, CloudFront
- Future: Separate client accounts for commissioned work

---

## Migration Scenarios

### Scenario 1: No Infrastructure Deployed Yet (Greenfield)

**Status**: No AWS resources exist, only Terraform code

**Recommendation**: **Use new multi-account architecture directly**

**Steps**:
1. Follow deployment guide in [CLAUDE.md](./CLAUDE.md)
2. Deploy Phase 1: Management account (organization, SSO, SCPs, state backend)
3. Deploy Phase 2: Whollyowned account (rbac, state backend, domains, sites)
4. Deploy Phase 3: Cross-account wiring (NS records)

**No migration needed** - start fresh with multi-account structure.

---

### Scenario 2: Infrastructure Already Deployed (Brownfield)

**Status**: Existing single-account infrastructure is live in production

**Recommendation**: **Carefully planned migration with zero downtime**

**Migration Complexity**: **High** - involves cross-account resource moves, DNS changes, state migrations

**Migration Options**:

#### Option A: In-Place Upgrade (Advanced)
Convert existing account to whollyowned account, create new management account, enable Organizations.

**Pros**:
- Preserves existing resources (no recreation)
- Minimal DNS downtime (NS record updates only)
- State files can be migrated without destroying resources

**Cons**:
- Complex Terraform state manipulation required
- Risk of state corruption if not done carefully
- Requires deep Terraform expertise

**Estimated Time**: 2-4 hours (careful planning required)

#### Option B: Side-by-Side Migration (Recommended)
Create new multi-account infrastructure alongside existing, migrate DNS gradually.

**Pros**:
- Low risk (existing infrastructure untouched until cutover)
- Can test new infrastructure before cutover
- Easy rollback if issues arise
- Clear separation of old vs new

**Cons**:
- Temporary duplicate resources (temporary cost increase)
- Requires coordinating DNS cutover
- More steps overall

**Estimated Time**: 4-8 hours (spread across days for testing)

#### Option C: Clean Slate (Not Recommended for Production)
Destroy existing infrastructure, deploy new multi-account architecture.

**Pros**:
- Simplest approach (no migration complexity)
- Guaranteed clean state

**Cons**:
- **Downtime**: Websites offline during migration
- **Data loss risk**: S3 content must be backed up and restored
- **DNS propagation**: Can take 24-48 hours
- **Unacceptable for production websites**

**Only use if**: Existing infrastructure is test/development only

---

## Detailed Migration: Option B (Side-by-Side)

### Phase 1: Create New Management Account

**Goal**: Set up AWS Organizations with management account

#### Step 1: Create New AWS Account (Management)

**Option A: Convert Existing Account** (if existing account has no production resources):
1. Log in to existing AWS account as root user
2. Navigate to AWS Organizations
3. Enable Organizations (this account becomes management account)
4. Note: **This cannot be undone** - organization cannot be disabled if it has member accounts

**Option B: Create Separate Management Account** (recommended):
1. Sign up for new AWS account: `aws-management@noise2signal.com`
2. This becomes management account
3. Existing account will be invited/moved to organization later

#### Step 2: Deploy Management Account Layers

**Warning**: Use a different state bucket name to avoid conflicts with existing infrastructure

```bash
# Clone repository (if not already cloned)
git clone https://github.com/noise2signal/iac-aws.git
cd iac-aws

# Ensure you're on latest multi-account architecture
git pull origin main

# Configure AWS CLI with NEW management account
aws configure --profile management-admin

# Deploy organization layer
cd management/organization
# Edit terraform.tfvars:
# whollyowned_account_email = "aws-whollyowned-new@noise2signal.com"  # Use NEW email
terraform init
terraform apply
# Note whollyowned account ID

# Deploy SSO layer
cd ../sso
# Edit terraform.tfvars with whollyowned account ID
terraform init
terraform apply
# Create boss SSO user, configure MFA

# Deploy SCP layer
cd ../scp
# Edit terraform.tfvars with OU IDs
terraform init
terraform apply

# Optional: Deploy state backend
cd ../tfstate-backend
terraform init
terraform apply
# Migrate management layers to remote state
```

**Result**: Management account configured with Organizations, SSO, SCPs

---

### Phase 2: Set Up New Whollyowned Account

**Goal**: Deploy production website infrastructure in new whollyowned account

#### Step 1: Access Whollyowned Account

```bash
# Option A: Via SSO (after SSO layer deployed)
aws sso login --profile whollyowned-admin

# Option B: Via assume-role from management account
aws sts assume-role \
  --role-arn arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/OrganizationAccountAccessRole \
  --role-session-name migration
```

#### Step 2: Deploy Whollyowned Account Layers

```bash
# Deploy RBAC layer (IAM roles + OIDC)
cd whollyowned/rbac
terraform init
terraform apply

# Optional: Deploy state backend
cd ../tfstate-backend
terraform init
terraform apply
# Migrate whollyowned layers to remote state

# Deploy domains layer (Route53 zones + ACM)
cd ../domains
# Edit terraform.tfvars:
# domains = {
#   "camdenwander.com" = { ... },
# }
terraform init
terraform apply
# Wait for ACM certificate validation (5-10 min)

# Deploy sites layer (S3 + CloudFront + DNS)
cd ../sites
# Edit terraform.tfvars:
# sites = {
#   "camdenwander.com" = { ... },
# }
terraform init
terraform apply
# Wait for CloudFront deployment (15-30 min)
```

**Result**: New infrastructure ready, but NOT receiving traffic yet (DNS not updated)

---

### Phase 3: Migrate Domain Registrations

**Goal**: Transfer domain registrations to management account, update NS records

#### Step 1: Transfer Domain Registrations

**If domains registered in old AWS account**:
1. Initiate transfer from old account to management account
2. Or: Keep domains in old account (but update NS records to point to new hosted zones)

**If domains registered with external registrar** (e.g., Namecheap, GoDaddy):
1. Transfer domains to Route53 in management account
2. Or: Update NS records at external registrar to point to new Route53 hosted zones

#### Step 2: Update NS Records

```bash
# In whollyowned account: Get NS records from NEW hosted zone
aws route53 list-hosted-zones --profile whollyowned-admin
aws route53 list-resource-record-sets \
  --hosted-zone-id <NEW_ZONE_ID> \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value" \
  --output text

# In management account: Update domain nameservers
aws route53domains update-domain-nameservers \
  --region us-east-1 \
  --profile management-admin \
  --domain-name camdenwander.com \
  --nameservers Name=ns-123.awsdns-12.com Name=ns-456.awsdns-45.net ...
```

**Result**: Domain NS records point to new Route53 hosted zones in whollyowned account

**DNS Propagation**: Changes take 5-60 minutes to propagate globally

---

### Phase 4: Migrate Website Content

**Goal**: Copy S3 content from old account to new account

#### Step 1: Copy S3 Content

**Option A: Direct S3 sync** (if you have access to both accounts):
```bash
# Sync from old account to local
aws s3 sync s3://old-camdenwander-bucket/ ./website-backup/ \
  --profile old-account

# Sync from local to new account
aws s3 sync ./website-backup/ s3://camdenwander.com/ \
  --profile whollyowned-admin \
  --delete
```

**Option B: Use S3 cross-account replication** (for large sites):
1. Set up replication from old bucket to new bucket
2. Wait for replication to complete
3. Verify content integrity

#### Step 2: Invalidate CloudFront Cache

```bash
# In new whollyowned account
aws cloudfront create-invalidation \
  --distribution-id <NEW_DISTRIBUTION_ID> \
  --paths "/*" \
  --profile whollyowned-admin
```

**Result**: New CloudFront distribution serves same content as old

---

### Phase 5: Cutover & Validation

**Goal**: Verify new infrastructure is serving traffic correctly

#### Step 1: Test New Infrastructure

**Before updating DNS**:
1. Add new CloudFront domain to `/etc/hosts` for testing:
   ```
   # Get CloudFront distribution domain
   aws cloudfront get-distribution --id <NEW_DIST_ID> \
     --query 'Distribution.DomainName' --output text

   # Add to /etc/hosts (requires sudo)
   sudo echo "1.2.3.4  camdenwander.com" >> /etc/hosts  # Use CloudFront IP
   ```

2. Test website in browser: `http://camdenwander.com`
3. Verify SSL certificate is valid
4. Test all pages, forms, links

#### Step 2: Monitor DNS Propagation

After updating NS records in Phase 3:

```bash
# Check DNS propagation globally
dig camdenwander.com @8.8.8.8  # Google DNS
dig camdenwander.com @1.1.1.1  # Cloudflare DNS

# Both should show new CloudFront distribution IP
```

#### Step 3: Monitor Traffic Shift

**CloudWatch Metrics** (in new whollyowned account):
- CloudFront requests increasing
- S3 requests increasing (from CloudFront OAC)

**Old Account CloudWatch**:
- CloudFront requests decreasing
- Should reach zero within 24-48 hours

#### Step 4: Validate Website Functionality

- [ ] Website loads correctly
- [ ] SSL certificate valid (no browser warnings)
- [ ] All pages accessible
- [ ] Forms submit successfully
- [ ] No broken links
- [ ] Images/CSS/JS loading correctly
- [ ] Mobile responsive design working

---

### Phase 6: Decommission Old Infrastructure

**Goal**: Remove old infrastructure after successful migration

**Wait Period**: **7 days minimum** after DNS cutover

**Validation Checklist**:
- [ ] New infrastructure has been stable for 7+ days
- [ ] No traffic hitting old CloudFront distribution
- [ ] No errors in CloudWatch logs
- [ ] Website analytics show normal traffic levels
- [ ] Boss has signed off on migration success

#### Step 1: Destroy Old Infrastructure

**In old AWS account**:

```bash
# Backup state files first!
cd /old-terraform-directory
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# Destroy in reverse order
cd sites
terraform destroy

cd ../domains
terraform destroy

cd ../rbac
terraform destroy

cd ../tfstate-backend
terraform destroy

cd ../scp
terraform destroy
```

**Warning**: `terraform destroy` is **irreversible** - ensure backups exist before proceeding

#### Step 2: Close Old AWS Account (Optional)

**Only if old account has no other resources**:

1. Log in as root user to old account
2. Navigate to "Account Settings"
3. Scroll to "Close Account"
4. Follow prompts (requires verification)
5. **Cannot be undone for 90 days**

**Alternative**: Keep old account in organization as Sandbox OU (for experimentation)

---

## Migration Risks & Mitigations

### Risk 1: DNS Propagation Delay

**Risk**: Users may see old site for 24-48 hours during DNS propagation

**Mitigation**:
- Lower TTL on DNS records to 300 seconds (5 minutes) 24 hours BEFORE migration
- Schedule migration during low-traffic period (e.g., weekend)
- Monitor both old and new infrastructure during cutover

### Risk 2: SSL Certificate Issues

**Risk**: New ACM certificate not validated in time, causing HTTPS errors

**Mitigation**:
- Deploy domains layer 24 hours before cutover (ACM validation takes 5-10 min)
- Verify certificate status before updating DNS: `aws acm describe-certificate`
- Test HTTPS with CloudFront domain before DNS cutover

### Risk 3: S3 Content Mismatch

**Risk**: New S3 bucket missing files, causing 404 errors

**Mitigation**:
- Use `aws s3 sync` with `--dryrun` first to verify file counts
- Compare file counts: `aws s3 ls s3://old-bucket --recursive | wc -l`
- Keep old S3 bucket read-only for 7 days (don't delete)

### Risk 4: State File Corruption

**Risk**: Terraform state becomes corrupted during migration, causing drift

**Mitigation**:
- **Always backup state files** before any Terraform operation
- Use `terraform plan` extensively (never apply without reviewing plan)
- Keep old state files in S3 versioning (90-day retention)
- If state corruption occurs, restore from backup and retry

### Risk 5: Permissions Issues

**Risk**: IAM roles misconfigured, preventing Terraform operations

**Mitigation**:
- Test IAM roles after RBAC layer deployment
- Use `aws sts get-caller-identity` to verify role assumption
- Have SSO admin access as fallback (can always fix IAM issues)

---

## Rollback Plan

**If migration fails**, rollback to old infrastructure:

### Step 1: Revert DNS Changes

```bash
# In old account: Get OLD hosted zone NS records
aws route53 list-resource-record-sets \
  --hosted-zone-id <OLD_ZONE_ID> \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value"

# Update domain registrar to use OLD NS records
# (Same process as Phase 3, but with old NS records)
```

### Step 2: Wait for DNS Propagation

**Timeline**: 5-60 minutes (if TTL was lowered to 300s)

### Step 3: Verify Old Site Active

```bash
# Test old site
dig camdenwander.com  # Should show old CloudFront IP
curl https://camdenwander.com  # Should load old site
```

### Step 4: Investigate Failure

**Common Issues**:
- CloudFront distribution not deployed correctly
- ACM certificate validation failed
- S3 content missing or incorrect
- IAM permissions blocking access

**Resolution**: Fix issue in new infrastructure, retry cutover later

### Step 5: Keep New Infrastructure

**Don't destroy new infrastructure immediately** - troubleshoot and retry migration once issues are resolved.

---

## Post-Migration Tasks

### 1. Update Documentation

- [ ] Update README.md with new account structure
- [ ] Document new deployment workflows
- [ ] Update runbooks for incident response

### 2. Update Billing Alerts

- [ ] Set up billing alerts in management account (consolidated billing)
- [ ] Configure per-account cost allocation tags
- [ ] Review first month's bill for accuracy

### 3. Update Team Access

- [ ] Onboard team members to SSO (IAM Identity Center)
- [ ] Grant appropriate permission sets (Admin, PowerUser, ReadOnly)
- [ ] Disable old IAM users in old account (if decommissioned)

### 4. Update CI/CD Pipelines (Future)

- [ ] Update GitHub Actions workflows for new account structure
- [ ] Configure GitHub OIDC trust relationships
- [ ] Test automated deployments

### 5. Backup & Disaster Recovery

- [ ] Verify S3 versioning enabled on state buckets
- [ ] Document state file recovery procedures
- [ ] Test disaster recovery plan (restore from backup)

---

## Timeline Estimate

**Total Migration Time**: 1-2 weeks (spread across days for testing and validation)

**Detailed Timeline**:

| Phase | Duration | Can Be Parallelized? |
|-------|----------|----------------------|
| Phase 1: Create Management Account | 2-4 hours | No (prerequisite for others) |
| Phase 2: Set Up Whollyowned Account | 2-4 hours | After Phase 1 complete |
| Phase 3: Migrate Domain Registrations | 1-2 hours | After Phase 2 complete |
| **DNS Propagation Wait** | **24-48 hours** | **Passive wait** |
| Phase 4: Migrate Website Content | 1-2 hours | During DNS propagation |
| Phase 5: Cutover & Validation | 4-8 hours | After DNS propagation |
| **Stability Wait Period** | **7 days** | **Passive monitoring** |
| Phase 6: Decommission Old Infrastructure | 1-2 hours | After 7-day wait |

**Total Active Work**: 11-21 hours
**Total Calendar Time**: 10-16 days (including wait periods)

---

## Questions & Support

**Before starting migration**:
1. Is production website traffic currently low enough for planned downtime?
2. Do you have backups of all S3 content?
3. Do you have access to domain registrar (to update NS records)?
4. Are you comfortable with Terraform state manipulation?

**If unsure**: Consider Option B (Side-by-Side) for lowest risk, or engage AWS Professional Services for migration assistance.

---

## References

- [AWS Organizations Migration Guide](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html)
- [Route53 Domain Transfer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-transfer.html)
- [Terraform State Management](https://www.terraform.io/docs/language/state/index.html)

---

**Document Version**: 1.0
**Last Updated**: 2026-01-26
**Maintained By**: Noise2Signal LLC Infrastructure Team
