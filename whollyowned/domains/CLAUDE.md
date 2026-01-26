# Whollyowned Account - Domains Layer (Route53 Zones + ACM)

## Purpose

The **domains layer** creates Route53 hosted zones and ACM certificates for all wholly-owned domains in the **whollyowned account**. This layer manages public DNS and SSL/TLS certificates, but NOT domain registrations (those live in the management account).

**This is Layer 2** - deployed after RBAC and tfstate-backend layers.

---

## Responsibilities

1. **Create Route53 hosted zones** (public DNS for each domain)
2. **Create ACM certificates** (SSL/TLS for HTTPS, DNS validation)
3. **Configure DNS validation records** (CNAME records for ACM validation)
4. **Output nameservers** (for manual update in management account domain registrations)
5. **Output certificate ARNs** (for use by sites layer)
6. **Manage CAA records** (optional, restrict certificate issuance to AWS)

**Design Goal**: Centralize DNS and certificate management for all wholly-owned domains, separate from website infrastructure (sites layer).

---

## Cross-Account Dependency

**Important**: Domain registrations live in the **management account**, but hosted zones live in the **whollyowned account**.

**Manual Step Required** (Phase 3 of bootstrap):
1. Deploy this layer (creates hosted zones in whollyowned account)
2. Note nameserver (NS) records from Terraform outputs
3. Switch to management account
4. Update domain registration nameservers to point to whollyowned hosted zone NS records

**Why Manual**: Terraform cannot easily update cross-account Route53 domain registrations. This is a one-time setup step per domain.

**Future Enhancement**: Automate with Terraform data sources or Lambda function.

---

## Resources Created

### Route53 Hosted Zone (Per Domain)

```hcl
# Use local module for each domain
module "domain_camdenwander_com" {
  source = "../../modules/domain"

  domain_name = "camdenwander.com"
  create_caa_record = true  # Optional: restrict certificate issuance to AWS

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "domains"
    Domain       = "camdenwander.com"
  }
}
```

**Module creates**:
- Route53 hosted zone (public DNS)
- ACM certificate (us-east-1, for CloudFront)
- DNS validation records (CNAME records in hosted zone)
- CAA record (optional, restricts certificate issuance)

**Hosted Zone**: `camdenwander.com` (public)
**Region**: `us-east-1` (Route53 is global, but resources are in us-east-1)

### ACM Certificate (Per Domain)

**Provider**: `aws.us_east_1` (CloudFront requires certificates in us-east-1)

```hcl
# Inside domain module
resource "aws_acm_certificate" "this" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain_name}",  # Wildcard for subdomains (e.g., www.camdenwander.com)
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Domain = var.domain_name
  })
}
```

**Validation Method**: DNS (CNAME records added to hosted zone automatically)
**Subject Alternative Names**: `camdenwander.com`, `*.camdenwander.com`
**Renewal**: Automatic (AWS ACM handles renewal 60 days before expiration)

### DNS Validation Records (Automatic)

```hcl
# Inside domain module
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```

**Purpose**: Prove domain ownership to AWS ACM for certificate issuance.

**Timeline**: ~5-10 minutes (after NS records updated in management account).

### CAA Record (Optional)

```hcl
# Inside domain module (if var.create_caa_record = true)
resource "aws_route53_record" "caa" {
  count   = var.create_caa_record ? 1 : 0
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 300

  records = [
    "0 issue \"amazon.com\"",
    "0 issuewild \"amazon.com\"",
  ]
}
```

**Purpose**: Restrict certificate issuance to AWS only (prevents unauthorized certificate issuance by other CAs).

**Recommended**: Enable for production domains.

---

## Variables

### Required Variables

```hcl
variable "domains" {
  type = map(object({
    create_caa_record = bool
  }))
  description = "Map of domain names to configuration"
}
```

**Example** (in `terraform.tfvars`):

```hcl
domains = {
  "camdenwander.com" = {
    create_caa_record = true
  }
  # Add more domains here as needed
}
```

### Optional Variables

```hcl
variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
  }
}
```

---

## Outputs

### Per-Domain Outputs

```hcl
output "hosted_zone_id_camdenwander_com" {
  value       = module.domain_camdenwander_com.hosted_zone_id
  description = "Hosted zone ID for camdenwander.com"
}

output "nameservers_camdenwander_com" {
  value       = module.domain_camdenwander_com.nameservers
  description = "Nameservers for camdenwander.com (update in management account)"
}

output "certificate_arn_camdenwander_com" {
  value       = module.domain_camdenwander_com.certificate_arn
  description = "ACM certificate ARN for camdenwander.com"
}

output "certificate_status_camdenwander_com" {
  value       = module.domain_camdenwander_com.certificate_status
  description = "ACM certificate validation status"
}
```

### Aggregated Outputs (for Sites Layer)

```hcl
output "domain_hosted_zones" {
  value = {
    for domain, config in var.domains : domain => {
      zone_id         = module.domain[domain].hosted_zone_id
      nameservers     = module.domain[domain].nameservers
      certificate_arn = module.domain[domain].certificate_arn
    }
  }
  description = "Map of domain names to hosted zone IDs, nameservers, and certificate ARNs"
}
```

---

## Authentication & Permissions

### Deployment Authentication

**Authentication**: Assumes `domains-terraform-role` (via GitHub Actions) or SSO admin (manual)

**AWS CLI Profile Setup** (for SSO admin manual deployment):

```bash
export AWS_PROFILE=whollyowned-admin
aws sso login --profile whollyowned-admin
```

**Required Permissions** (via `domains-terraform-role` from RBAC layer):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:UpdateHostedZoneComment",
        "route53:GetChange",
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets",
        "route53:GetHostedZoneCount",
        "route53:ListTagsForResource",
        "route53:ChangeTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "acm:RequestCertificate",
        "acm:DeleteCertificate",
        "acm:DescribeCertificate",
        "acm:ListCertificates",
        "acm:AddTagsToCertificate",
        "acm:RemoveTagsFromCertificate",
        "acm:GetCertificate"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note**: Cannot manage Route53 domain registrations (those are in management account only).

**Provider Configuration**:

```hcl
# provider.tf
provider "aws" {
  region = "us-east-1"

  # Optional: Assume domains-terraform-role (for GitHub Actions)
  # assume_role {
  #   role_arn     = "arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/domains-terraform-role"
  #   session_name = "terraform-domains"
  # }
}

# ACM certificates for CloudFront must be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  # Same assume_role as above (if using GitHub Actions)
}
```

**No Cross-Account Access**: This layer does NOT require access to the management account.

---

## State Management

### Initial State (Local)

```hcl
# backend.tf (initially commented out)
# terraform {
#   backend "s3" {
#     bucket         = "n2s-terraform-state-whollyowned"
#     key            = "whollyowned/domains.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-whollyowned-lock"
#     encrypt        = true
#   }
# }
```

### Remote State (After Layer 1)

After deploying `tfstate-backend` layer, uncomment `backend.tf` and migrate:

```bash
cd whollyowned/domains
terraform init -migrate-state
```

---

## Deployment

### Prerequisites

1. RBAC layer deployed (IAM roles exist)
2. Tfstate-backend layer deployed (optional, for remote state)
3. Management account has domain registrations (or ready to register domains)
4. AWS CLI configured with whollyowned SSO profile

### Step 1: Create terraform.tfvars

```hcl
# whollyowned/domains/terraform.tfvars
domains = {
  "camdenwander.com" = {
    create_caa_record = true
  }
  # Add more domains as needed
}
```

### Step 2: Initialize Terraform

```bash
cd whollyowned/domains
terraform init
```

### Step 3: Review Plan

```bash
terraform plan
```

**Expected Resources (per domain)**:
- 1 Route53 hosted zone
- 1 ACM certificate
- 1-2 DNS validation records (CNAME)
- 1 ACM certificate validation resource
- 1 CAA record (if enabled)

**Total per domain**: ~5 resources

### Step 4: Apply

```bash
terraform apply
```

**Timeline**: ~2-3 minutes (hosted zone + certificate request)

**Note**: Certificate will be in "Pending Validation" state until NS records are updated in management account (Phase 3).

### Step 5: Note Nameservers from Outputs

```bash
terraform output nameservers_camdenwander_com
# Expected: 4 nameservers (e.g., ns-123.awsdns-12.com, ns-456.awsdns-45.net, ...)
```

**Copy these nameservers** - you'll need them for Phase 3 (cross-account wiring).

---

## Phase 3: Cross-Account Nameserver Update

**Manual Step**: Update domain nameservers in management account to point to whollyowned hosted zone.

### Step 1: Switch to Management Account

```bash
aws sso login --profile management-admin
```

### Step 2: Get Nameservers from Whollyowned Account

```bash
cd whollyowned/domains
terraform output nameservers_camdenwander_com
# Copy the 4 nameserver values
```

### Step 3: Update Domain Registration (Management Account)

**Option A: AWS CLI**

```bash
aws route53domains update-domain-nameservers \
  --region us-east-1 \
  --domain-name camdenwander.com \
  --nameservers \
    Name=ns-123.awsdns-12.com \
    Name=ns-456.awsdns-45.net \
    Name=ns-789.awsdns-78.org \
    Name=ns-012.awsdns-01.co.uk \
  --profile management-admin
```

**Option B: AWS Console**

1. Log into management account (via SSO)
2. Navigate to Route53 → Registered domains
3. Select `camdenwander.com`
4. Click "Add or edit name servers"
5. Replace nameservers with values from whollyowned hosted zone
6. Save changes

### Step 4: Wait for DNS Propagation

```bash
# Check NS records (should show whollyowned nameservers)
dig NS camdenwander.com
# or
nslookup -type=NS camdenwander.com
```

**Timeline**: Usually 5-10 minutes, can take up to 48 hours

### Step 5: Verify ACM Certificate Validation

After DNS propagation:

```bash
# Switch back to whollyowned account
cd whollyowned/domains
terraform refresh

# Check certificate status
terraform output certificate_status_camdenwander_com
# Expected: "ISSUED" (after validation completes)
```

**Timeline**: ~5-10 minutes after NS records are updated

---

## Post-Deployment Tasks

### 1. Verify Hosted Zone

```bash
# List resource record sets in hosted zone
ZONE_ID=$(terraform output -raw hosted_zone_id_camdenwander_com)
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --profile whollyowned-admin
```

**Expected Records**:
- NS (nameservers)
- SOA (start of authority)
- CNAME (ACM validation records)
- CAA (if enabled)

### 2. Verify ACM Certificate

```bash
# Describe certificate
CERT_ARN=$(terraform output -raw certificate_arn_camdenwander_com)
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --profile whollyowned-admin
```

**Expected Status**: `ISSUED` (after validation completes)

### 3. Test DNS Resolution

```bash
# Query DNS (should resolve via whollyowned hosted zone)
dig camdenwander.com
dig www.camdenwander.com

# Check nameservers
dig NS camdenwander.com
# Should show whollyowned hosted zone nameservers
```

### 4. Proceed to Next Layer

**Next**: Deploy `whollyowned/sites` layer (S3 + CloudFront + DNS records)

See [../sites/CLAUDE.md](../sites/CLAUDE.md)

---

## Adding a New Domain

### Step 1: Add to terraform.tfvars

```hcl
# whollyowned/domains/terraform.tfvars
domains = {
  "camdenwander.com" = {
    create_caa_record = true
  },
  "newdomain.com" = {  # Added
    create_caa_record = true
  }
}
```

### Step 2: Apply Changes

```bash
cd whollyowned/domains
terraform apply
```

### Step 3: Get Nameservers for New Domain

```bash
terraform output nameservers_newdomain_com
```

### Step 4: Update Domain Registration (Management Account)

Follow Phase 3 steps above for the new domain.

### Step 5: Wait for Certificate Validation

```bash
terraform output certificate_status_newdomain_com
# Expected: "ISSUED" (after NS records updated and DNS propagated)
```

---

## Troubleshooting

### Certificate Validation Stuck "Pending Validation"

**Symptoms**: ACM certificate status remains "Pending Validation" for >10 minutes

**Cause**: NS records not updated in management account, or DNS propagation delay

**Resolution**:

1. Verify nameservers in management account domain registration match whollyowned hosted zone NS records
2. Check DNS propagation: `dig NS camdenwander.com` (should show whollyowned nameservers)
3. Wait for DNS propagation (can take up to 48 hours, usually 5-10 minutes)
4. If NS records are correct, wait and check again later
5. If still stuck after 48 hours, delete and re-create certificate

### Error: Hosted Zone Already Exists

**Symptoms**: `terraform apply` fails with "Hosted zone with name X already exists"

**Cause**: Hosted zone already created (manual or previous deployment)

**Resolution**:

```bash
# Import existing hosted zone into Terraform state
terraform import module.domain_camdenwander_com.aws_route53_zone.this <ZONE_ID>

# Re-run apply
terraform apply
```

### Error: Cannot Create ACM Certificate in us-east-1

**Symptoms**: `terraform apply` fails with "Certificate could not be created in us-east-1"

**Cause**: Provider alias not configured, region mismatch, or API quota exceeded

**Resolution**:

1. Verify `provider "aws" { alias = "us_east_1" }` is configured in `provider.tf`
2. Verify module uses `provider = aws.us_east_1` for ACM certificate
3. Check ACM quota (default: 2500 certificates per region): `aws service-quotas list-service-quotas --service-code acm --region us-east-1 --profile whollyowned-admin`

### Error: DNS Validation Records Not Created

**Symptoms**: ACM certificate stuck in "Pending Validation", no CNAME records in hosted zone

**Cause**: Terraform failed to create validation records, or permissions issue

**Resolution**:

```bash
# Verify hosted zone ID is correct
terraform output hosted_zone_id_camdenwander_com

# Check if validation records exist
ZONE_ID=$(terraform output -raw hosted_zone_id_camdenwander_com)
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='CNAME']" \
  --profile whollyowned-admin

# If missing, re-run apply
terraform apply
```

### Nameservers Not Updating in Management Account

**Symptoms**: `aws route53domains update-domain-nameservers` fails or times out

**Cause**: Domain locked, invalid nameserver format, API issue

**Resolution**:

1. Verify domain is unlocked: `aws route53domains get-domain-detail --domain-name camdenwander.com --region us-east-1 --profile management-admin`
2. Verify nameserver format (must be `Name=ns-123.awsdns-12.com`, not full ARN or IP)
3. If locked, unlock domain first (registrar lock, transfer lock)
4. Retry update after a few minutes (API may be temporarily unavailable)

---

## Cost Considerations

### Route53 Hosted Zone

**Cost**: $0.50/month per hosted zone

**Queries**: $0.40 per million queries (first 1 billion queries)
- Typical small website: <1 million queries/month
- Estimated cost: <$0.40/month per domain

**Total per domain**: ~$0.90/month

### ACM Certificates

**Cost**: Free (when used with CloudFront or other AWS services)

**Renewal**: Automatic (no manual intervention or cost)

### DNS Queries (External)

**CloudFlare DNS** (alternative, not used): Free tier available

**AWS Route53**: Pay-per-query model (see above)

### Total Cost (Per Domain)

```
Route53 hosted zone:     $0.50/month
Route53 queries:         ~$0.40/month (1M queries)
ACM certificate:         Free
──────────────────────────
Total per domain:        ~$0.90/month
```

**Scaling**: Each additional domain adds ~$0.90/month

**Included in**: Whollyowned account cost allocation (CostCenter: whollyowned)

---

## Security Considerations

### CAA Records

**Purpose**: Restrict certificate issuance to AWS only

**Benefit**: Prevents unauthorized certificate issuance by other certificate authorities (CAs)

**Recommendation**: Enable for all production domains (`create_caa_record = true`)

**CAA Record Format**:
```
0 issue "amazon.com"       # Allow AWS to issue certificates
0 issuewild "amazon.com"   # Allow AWS to issue wildcard certificates
```

### DNSSEC (Optional)

**Not implemented**: Route53 supports DNSSEC (domain signing), but adds complexity

**Future Enhancement**: Enable DNSSEC for enhanced security (prevents DNS spoofing)

### Certificate Renewal

**AWS ACM handles automatic renewal** (60 days before expiration)

**Monitoring**: ACM sends email alerts if renewal fails (verify email address in management account)

**Fallback**: Manual re-validation via DNS (same CNAME records)

### Domain Transfer Lock

**Enabled in management account**: Prevents unauthorized domain transfers

**Registrar Lock**: Prevents domain from being transferred to another registrar without authorization

**Verify**: `aws route53domains get-domain-detail --domain-name camdenwander.com --region us-east-1 --profile management-admin`

---

## References

### Related Layers

- [../CLAUDE.md](../CLAUDE.md) - Whollyowned account overview
- [../rbac/CLAUDE.md](../rbac/CLAUDE.md) - RBAC layer (creates IAM roles)
- [../tfstate-backend/CLAUDE.md](../tfstate-backend/CLAUDE.md) - State backend layer
- [../sites/CLAUDE.md](../sites/CLAUDE.md) - Next layer (uses certificates from this layer)

### Module Documentation

- [../../modules/domain/CLAUDE.md](../../modules/domain/CLAUDE.md) - Domain module (Route53 + ACM pattern)

### Parent Documentation

- [../../CLAUDE.md](../../CLAUDE.md) - Overall architecture
- [../../management/CLAUDE.md](../../management/CLAUDE.md) - Management account (domain registrations)

### AWS Documentation

- [Route53 Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html)
- [ACM Certificate Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [Route53 Domain Registration](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html)
- [CAA Records](https://docs.aws.amazon.com/acm/latest/userguide/setup-caa.html)

---

**Layer**: 2 (Domains)
**Account**: noise2signal-llc-whollyowned
**Last Updated**: 2026-01-26
