# Terraform DNS Domains - Domain Ownership Layer

## Repository Purpose

This repository manages **domain ownership infrastructure** for Noise2Signal LLC, including Route53 hosted zones and ACM certificates. This is the authoritative source for all DNS zones and SSL/TLS certificates used across Noise2Signal productions.

**GitHub Repository**: `terraform-dns-domains`

## Scope & Responsibilities

### In Scope
✅ **Route53 Hosted Zones**
- Hosted zone creation for all Noise2Signal domains
- Zone configuration (DNSSEC, query logging if needed)
- Name server delegation records
- CAA records (certificate authority authorization)

✅ **ACM SSL/TLS Certificates**
- Certificates for CloudFront (must be in us-east-1)
- DNS validation via Route53
- Certificate lifecycle management (automatic renewal)
- Subject Alternative Names (SANs) for apex + www subdomains

✅ **DNS Validation Records**
- Automatic creation of ACM validation CNAMEs in Route53
- Validation completion verification

### Out of Scope
❌ Application DNS records (A, AAAA, CNAME pointing to CloudFront) - managed in `terraform-static-sites`
❌ S3 buckets - managed in `terraform-static-sites`
❌ CloudFront distributions - managed in `terraform-static-sites`
❌ State backend infrastructure - managed in `terraform-inception`
❌ Domain registration transfers (manual pre-Terraform step)

## Architecture Context

### Multi-Repo Strategy
This repo is **Tier 2** in a 3-tier architecture:

1. **Tier 1: terraform-inception**
   - Terraform harness (state backend, execution roles)

2. **Tier 2: terraform-dns-domains** ← YOU ARE HERE
   - Domain ownership (Route53 zones, ACM certificates)

3. **Tier 3: terraform-static-sites**
   - Website infrastructure (S3, CloudFront, Route53 records)

### Dependency Flow
```
terraform-inception (state backend)
        ↓
terraform-dns-domains (zones + certs)
        ↓
terraform-static-sites (references zones/certs via data sources)
```

### State File Location

```
s3://noise2signal-terraform-state/
└── noise2signal/
    ├── inception.tfstate
    ├── dns-domains.tfstate         ← This repo's state
    └── static-sites.tfstate
```

## Domain Portfolio

### Current Domains (Wholly-Owned)
This repository manages DNS for Noise2Signal LLC's wholly-owned domains:

1. **camden-wander.com** (initial/primary)
2. Domain 2 (TBD)
3. Domain 3 (TBD)
4. Domain 4 (TBD)
5. Domain 5 (TBD)

### Domain Onboarding Process

**Pre-Terraform Steps (Manual):**
1. Purchase domain or initiate transfer to Route53
2. Unlock domain at current registrar
3. Obtain transfer authorization code
4. Initiate transfer via AWS Console or CLI
5. Approve transfer email
6. Wait for transfer completion (5-7 days)

**Terraform Steps:**
1. Add domain to `domains` variable in `terraform.tfvars`
2. Run `terraform plan` to preview zone and certificate creation
3. Apply changes
4. Verify name server delegation (if transferred from external registrar)
5. Confirm certificate validation completes

## Resources Managed

### 1. Route53 Hosted Zones

One hosted zone per domain, created using `for_each` over domain list.

**Configuration per zone:**
```hcl
resource "aws_route53_zone" "domain" {
  for_each = toset(var.domains)

  name    = each.value
  comment = "Managed by Terraform - Noise2Signal LLC"

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Terraform   = "true"
    Domain      = each.value
  }
}
```

**Features:**
- DNSSEC: Optional (consider enabling for security)
- Query logging: Optional (consider cost vs benefit)
- Delegation set: Optional (consistent name servers across zones)

### 2. CAA Records (Optional but Recommended)

Restrict certificate issuance to AWS Certificate Manager only:

```hcl
resource "aws_route53_record" "caa" {
  for_each = toset(var.domains)

  zone_id = aws_route53_zone.domain[each.key].zone_id
  name    = each.value
  type    = "CAA"
  ttl     = 300

  records = [
    "0 issue \"amazon.com\"",
    "0 issuewild \"amazon.com\"",
  ]
}
```

### 3. ACM Certificates (us-east-1 Only)

**Critical**: Certificates MUST be created in `us-east-1` for CloudFront compatibility.

**Configuration per domain:**
```hcl
resource "aws_acm_certificate" "domain" {
  provider = aws.us_east_1  # Explicit provider for us-east-1

  for_each = toset(var.domains)

  domain_name               = each.value
  subject_alternative_names = ["www.${each.value}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Terraform   = "true"
    Domain      = each.value
  }
}
```

**Subject Alternative Names (SANs):**
- Apex domain: `camden-wander.com`
- WWW subdomain: `www.camden-wander.com`

### 4. ACM DNS Validation Records

Automatically created in Route53:

```hcl
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in flatten([
      for cert in aws_acm_certificate.domain : cert.domain_validation_options
    ]) : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
      zone_id = aws_route53_zone.domain[
        replace(dvo.domain_name, "www.", "")
      ].zone_id
    }
  }

  name    = each.value.name
  type    = each.value.type
  zone_id = each.value.zone_id
  records = [each.value.record]
  ttl     = 60
}
```

### 5. ACM Certificate Validation Wait

Ensures certificate is fully validated before downstream resources depend on it:

```hcl
resource "aws_acm_certificate_validation" "domain" {
  provider = aws.us_east_1

  for_each = toset(var.domains)

  certificate_arn         = aws_acm_certificate.domain[each.key].arn
  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation : record.fqdn
    if can(regex(each.value, record.fqdn))
  ]
}
```

## Terraform Configuration Standards

### Backend Configuration

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "noise2signal-terraform-state"
    key            = "noise2signal/dns-domains.tfstate"
    region         = "us-east-1"
    dynamodb_table = "noise2signal-terraform-state-lock"
    encrypt        = true
  }
}
```

### Provider Configuration

**Dual-region requirement**: Default region + us-east-1 for ACM.

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Owner     = "Noise2Signal LLC"
      Terraform = "true"
      ManagedBy = "terraform-dns-domains"
    }
  }
}

# ACM certificates for CloudFront MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Owner     = "Noise2Signal LLC"
      Terraform = "true"
      ManagedBy = "terraform-dns-domains"
    }
  }
}
```

### Variables

```hcl
variable "aws_region" {
  description = "Primary AWS region (Route53 is global)"
  type        = string
  default     = "us-east-1"
}

variable "domains" {
  description = "List of domains to manage (zones + certificates)"
  type        = list(string)

  validation {
    condition = alltrue([
      for d in var.domains : can(regex("^[a-z0-9-]+\\.[a-z]{2,}$", d))
    ])
    error_message = "Domains must be valid DNS names (lowercase, no www prefix)."
  }
}

variable "enable_dnssec" {
  description = "Enable DNSSEC for hosted zones"
  type        = bool
  default     = false  # Requires additional configuration
}

variable "enable_query_logging" {
  description = "Enable Route53 query logging (additional cost)"
  type        = bool
  default     = false
}
```

**Example terraform.tfvars:**
```hcl
domains = [
  "camden-wander.com",
  # Add additional domains as onboarded
]

enable_dnssec        = false
enable_query_logging = false
```

### Outputs

Outputs are consumed by `terraform-static-sites` via data sources:

```hcl
output "hosted_zone_ids" {
  description = "Map of domain names to Route53 zone IDs"
  value = {
    for domain, zone in aws_route53_zone.domain : domain => zone.zone_id
  }
}

output "hosted_zone_name_servers" {
  description = "Map of domain names to name server lists"
  value = {
    for domain, zone in aws_route53_zone.domain : domain => zone.name_servers
  }
}

output "certificate_arns" {
  description = "Map of domain names to ACM certificate ARNs (us-east-1)"
  value = {
    for domain, cert in aws_acm_certificate.domain : domain => cert.arn
  }
}

output "certificate_validation_status" {
  description = "Map of domain names to validation status"
  value = {
    for domain, cert in aws_acm_certificate.domain : domain => cert.status
  }
}
```

## Downstream Data Source Pattern

The `terraform-static-sites` repo references these resources using data sources (interim pattern before remote state):

```hcl
# In terraform-static-sites repo
data "aws_route53_zone" "site" {
  name = var.domain_name  # e.g., "camden-wander.com"
}

data "aws_acm_certificate" "site" {
  provider    = aws.us_east_1
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Usage:
# - data.aws_route53_zone.site.zone_id
# - data.aws_acm_certificate.site.arn
```

**Future**: Replace with `data.terraform_remote_state.dns_domains` when ready.

## Deployment Process

### Prerequisites
- `terraform-inception` deployed (state backend exists)
- AWS credentials configured (IAM role from inception)
- Domain transferred to Route53 OR ready to create new hosted zone

### Initial Deployment

1. **Clone repository**
   ```bash
   git clone https://github.com/noise2signal/terraform-dns-domains.git
   cd terraform-dns-domains
   ```

2. **Configure domains**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars - add camden-wander.com initially
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   # Backend should initialize with S3 state from inception repo
   ```

4. **Plan and review**
   ```bash
   terraform plan -out=tfplan
   # Review: zone creation, certificate request, validation records
   ```

5. **Apply**
   ```bash
   terraform apply tfplan
   ```

6. **Verify certificate validation**
   ```bash
   # Wait 5-10 minutes for DNS propagation and ACM validation
   terraform refresh
   terraform output certificate_validation_status
   # Should show "ISSUED" for all domains
   ```

7. **Verify name servers (if domain was transferred)**
   ```bash
   terraform output hosted_zone_name_servers
   # Compare with Route53 console or dig NS camden-wander.com
   ```

### Adding New Domains

1. Update `terraform.tfvars` - add domain to `domains` list
2. Run `terraform plan` - preview new zone and certificate
3. Apply changes
4. Verify certificate validation completes
5. Update `terraform-static-sites` repo to deploy website infrastructure

## Security Considerations

### Certificate Management
- Certificates are free via ACM when used with AWS services
- Automatic renewal (ACM handles renewal 60 days before expiration)
- DNS validation is secure (no email validation vulnerabilities)
- Certificates issued to "Noise2Signal LLC" as registrant

### Route53 Security
- Hosted zones are not publicly listable (require zone ID to query)
- CAA records prevent unauthorized certificate issuance
- DNSSEC (optional) prevents DNS spoofing attacks
- Zone transfer disabled by default (AWS-managed zones)

### Access Control
- Only Terraform execution roles can modify zones/certificates
- GitHub Actions role has scoped permissions (specific zones only)
- Developer role has broader access for prototyping

### Domain Hijacking Prevention
- Registrar lock enabled (configured in Route53 console or via AWS CLI)
- Transfer lock enabled
- Contact privacy enabled (WHOIS protection)
- Multi-factor auth on AWS account

## Dependencies

### Upstream Dependencies
- `terraform-inception` - State backend and IAM roles (implicit, not referenced)

### Downstream Dependencies
- `terraform-static-sites` - References zones and certificates via data sources

## Cost Estimates

**Per domain monthly costs:**
- Route53 hosted zone: $0.50/month
- Route53 queries: ~$0.40/1M queries (varies by traffic)
- ACM certificate: **Free** (when used with CloudFront)

**Total for 5 domains: ~$2.50/month + query costs**

## Testing & Validation

### Post-Deployment Checks
- [ ] Hosted zone exists for each domain
- [ ] Name servers are set correctly (if transferred)
- [ ] CAA records exist (if enabled)
- [ ] ACM certificate status is "ISSUED"
- [ ] DNS validation records exist in hosted zone
- [ ] Certificate covers apex + www subdomain

### Validation Commands

```bash
# Check hosted zone
aws route53 list-hosted-zones | grep camden-wander.com

# Check certificate validation
aws acm describe-certificate \
  --certificate-arn <ARN> \
  --region us-east-1 \
  | jq -r '.Certificate.Status'
# Should output: ISSUED

# Test DNS resolution
dig NS camden-wander.com +short
dig CAA camden-wander.com +short

# Verify cert can be discovered by data source
terraform console
> data.aws_acm_certificate.site.arn
```

## Maintenance & Updates

### Regular Maintenance
- Monitor certificate expiration dates (ACM renews automatically, but verify)
- Review query logs if enabled (identify unusual traffic patterns)
- Audit CAA records annually
- Update DNS records when infrastructure changes (handled by downstream repos)

### Certificate Renewal
- ACM handles renewal automatically 60 days before expiration
- Renewal uses same DNS validation records (no action required)
- If renewal fails, ACM sends email alerts to account contact

### Adding/Removing Domains
**Adding:**
1. Ensure domain is transferred to Route53 or ready for new zone
2. Add to `domains` variable in `terraform.tfvars`
3. Apply changes
4. Verify certificate validation

**Removing:**
1. First, destroy dependent resources in `terraform-static-sites` repo
2. Remove from `domains` variable
3. Apply changes (zone and certificate will be destroyed)
4. Consider domain transfer out if no longer needed

## Troubleshooting

### Certificate Validation Stuck "Pending"
**Symptoms**: Certificate status remains "PENDING_VALIDATION" after 10+ minutes

**Causes**:
- DNS validation record not created correctly
- DNS propagation delay
- Wrong hosted zone (validation record in wrong zone)

**Resolution**:
```bash
# Check validation records exist
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  | grep -A5 "_acm-challenge"

# Manually verify DNS record
dig _<random>.<domain> CNAME +short

# Force refresh
terraform refresh
terraform apply
```

### Name Server Delegation Issues
**Symptoms**: DNS queries fail, website unreachable

**Causes**:
- Name servers at registrar don't match Route53 zone
- Recent transfer, DNS propagation delay (24-48 hours)

**Resolution**:
```bash
# Get correct name servers
terraform output hosted_zone_name_servers

# Verify at registrar matches Route53 zone
# Use Route53 console or AWS CLI to confirm delegation
```

### Multiple Certificates for Same Domain
**Symptoms**: `terraform plan` shows certificate recreation

**Causes**:
- State drift (certificate created outside Terraform)
- Certificate in wrong region

**Resolution**:
```bash
# List all certificates for domain
aws acm list-certificates --region us-east-1 \
  | jq -r '.CertificateSummaryList[] | select(.DomainName == "camden-wander.com")'

# Import existing certificate if needed
terraform import aws_acm_certificate.domain["camden-wander.com"] <ARN>
```

## Future Enhancements

- DNSSEC configuration for enhanced security
- Route53 query logging to CloudWatch (traffic analysis)
- Automated domain renewal monitoring (alert before expiration)
- Multi-region certificate provisioning (if needed for regional services)
- Terraform remote state outputs (replace data source pattern)

## References

- [Route53 Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html)
- [ACM Certificate Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [CAA Records](https://docs.aws.amazon.com/acm/latest/userguide/setup-caa.html)
- [Route53 DNSSEC](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec.html)
