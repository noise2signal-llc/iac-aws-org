# Layer 3: Domains (Route53 + ACM)

## Layer Purpose

This layer manages **domain ownership infrastructure** for Noise2Signal LLC, including Route53 hosted zones and ACM SSL/TLS certificates. It uses the reusable `domain` module to provision DNS zones and certificates for each managed domain.

**Deployment Order**: Layer 3 (deployed after RBAC and optionally tfstate-backend)

## Scope & Responsibilities

### In Scope
✅ **Route53 Hosted Zones**
- Hosted zone creation for all managed domains
- Zone configuration (NS records, SOA records)
- CAA records (certificate authority authorization)
- DNS validation records for ACM certificates

✅ **ACM SSL/TLS Certificates**
- Certificates for CloudFront (must be in us-east-1)
- DNS validation via Route53
- Certificate lifecycle management (automatic renewal)
- Subject Alternative Names (SANs) for apex + www subdomains

✅ **Domain Module Integration**
- Iterate over domain map variable
- Call `domain` module per domain
- Output zone IDs and certificate ARNs for downstream layers

### Out of Scope
❌ Application DNS records (A, AAAA, CNAME) - managed in `sites` layer
❌ S3 buckets - managed in `sites` layer
❌ CloudFront distributions - managed in `sites` layer
❌ State backend infrastructure - managed in `tfstate-backend` layer
❌ IAM roles - managed in `rbac` layer
❌ Domain registration/transfers (manual pre-Terraform step)

## Architecture Context

### Layer Dependencies

```
Layer 0: scp (service constraints)
    ↓
Layer 1: rbac (IAM roles)
    ↓
Layer 2: tfstate-backend (S3 + DynamoDB) [optional]
    ↓
Layer 3: domains (Route53 + ACM) ← YOU ARE HERE
    ↓
Layer 4: sites (S3 + CloudFront + DNS records)
```

### State Management

**State Storage**: Local state file initially (`.tfstate` in this directory, gitignored)

**Backend Migration**: After `tfstate-backend` layer is deployed, uncomment `backend.tf` and run `terraform init -migrate-state`

**State Key**: `noise2signal/domains.tfstate` (in S3 after migration)

**Deployment Role**: `domains-terraform-role` (from RBAC layer)

## Domain Portfolio

### Current Domains (Wholly-Owned)

This layer manages DNS and certificates for Noise2Signal LLC's wholly-owned domains:

1. **camdenwander.com** (primary)
2. Additional domains TBD

### Domain Variable Structure

Domains are defined as a **map** with domain name as key:

```hcl
# terraform.tfvars
domains = {
  "camdenwander.com" = {
    enable_caa_records = true
    caa_issuers        = ["amazon.com"]
  }
  # Add additional domains as needed
}
```

**Why a map?**
- Easier to reference specific domain configurations
- Supports domain-specific options (CAA records, DNSSEC, etc.)
- Module iteration with `for_each` provides clear resource names

### Domain Onboarding Process

**Pre-Terraform Steps (Manual)**:
1. Purchase domain or initiate transfer to Route53
2. Unlock domain at current registrar
3. Obtain transfer authorization code
4. Initiate transfer via AWS Console or CLI
5. Approve transfer email
6. Wait for transfer completion (5-7 days)

**Terraform Steps**:
1. Add domain to `domains` variable in `terraform.tfvars`
2. Run `terraform plan` to preview zone and certificate creation
3. Apply changes
4. Verify name server delegation (if transferred from external registrar)
5. Confirm certificate validation completes (~5-10 minutes)

## Module Integration

This layer calls the `domain` module (located in `/workspace/modules/domain/`) for each domain.

### Module Call Pattern

```hcl
# main.tf
module "domain" {
  source = "../modules/domain"

  for_each = var.domains

  domain_name        = each.key
  enable_caa_records = each.value.enable_caa_records
  caa_issuers        = each.value.caa_issuers

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Layer       = "3-domains"
  }

  # ACM provider must be us-east-1 for CloudFront compatibility
  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}
```

### Module Expected Outputs

The `domain` module should expose:
- `hosted_zone_id` - Route53 zone ID (for DNS records in sites layer)
- `hosted_zone_name_servers` - NS records (for registrar configuration)
- `certificate_arn` - ACM certificate ARN (for CloudFront in sites layer)
- `certificate_status` - Validation status (should be "ISSUED")

### Layer Outputs (Aggregated from Module)

```hcl
# outputs.tf
output "hosted_zone_ids" {
  description = "Map of domain names to Route53 zone IDs"
  value = {
    for domain, module in module.domain : domain => module.hosted_zone_id
  }
}

output "hosted_zone_name_servers" {
  description = "Map of domain names to name server lists"
  value = {
    for domain, module in module.domain : domain => module.hosted_zone_name_servers
  }
}

output "certificate_arns" {
  description = "Map of domain names to ACM certificate ARNs (us-east-1)"
  value = {
    for domain, module in module.domain : domain => module.certificate_arn
  }
}

output "certificate_statuses" {
  description = "Map of domain names to certificate validation statuses"
  value = {
    for domain, module in module.domain : domain => module.certificate_status
  }
}
```

## Downstream Data Source Pattern

The `sites` layer references these resources using AWS data sources:

```hcl
# In sites/main.tf
data "aws_route53_zone" "site" {
  for_each = var.sites

  name         = each.value.domain_name
  private_zone = false
}

data "aws_acm_certificate" "site" {
  provider = aws.us_east_1  # Certificates must be in us-east-1 for CloudFront

  for_each = var.sites

  domain      = each.value.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Usage:
# zone_id = data.aws_route53_zone.site[each.key].zone_id
# certificate_arn = data.aws_acm_certificate.site[each.key].arn
```

**Why data sources instead of remote state?**
- Simpler to start with (no state dependencies)
- AWS data sources are reliable and well-tested
- Can migrate to remote state lookups later if needed

## Terraform Configuration

### Backend Configuration (Initially Commented)

```hcl
# backend.tf
# Uncomment after tfstate-backend layer is deployed

# terraform {
#   backend "s3" {
#     bucket         = "noise2signal-terraform-state"
#     key            = "noise2signal/domains.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "noise2signal-terraform-state-lock"
#     encrypt        = true
#   }
# }
```

### Provider Configuration

**Dual-region requirement**: Default region + us-east-1 for ACM (CloudFront certificates must be in us-east-1).

```hcl
# provider.tf
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

  # Assume domains-terraform-role from RBAC layer
  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/domains-terraform-role"
    session_name = "terraform-domains-session"
  }

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "domains-layer"
      Layer       = "3-domains"
    }
  }
}

# ACM certificates for CloudFront MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/domains-terraform-role"
    session_name = "terraform-domains-us-east-1-session"
  }

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "domains-layer"
      Layer       = "3-domains"
    }
  }
}
```

### Variables

```hcl
# variables.tf
variable "aws_region" {
  description = "Primary AWS region (Route53 is global, but set for consistency)"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID (for IAM role ARN construction)"
  type        = string
}

variable "domains" {
  description = "Map of domains to manage with configuration options"
  type = map(object({
    enable_caa_records = bool
    caa_issuers        = list(string)
  }))

  validation {
    condition = alltrue([
      for domain in keys(var.domains) : can(regex("^[a-z0-9-]+\\.[a-z]{2,}$", domain))
    ])
    error_message = "Domain names must be valid DNS names (lowercase, no www prefix)."
  }
}
```

### Example terraform.tfvars

```hcl
# terraform.tfvars
aws_account_id = "123456789012"  # Replace with actual account ID

domains = {
  "camdenwander.com" = {
    enable_caa_records = true
    caa_issuers        = ["amazon.com"]
  }
  # Add additional domains as onboarded:
  # "example.com" = {
  #   enable_caa_records = true
  #   caa_issuers        = ["amazon.com"]
  # }
}
```

## Deployment Process

### Prerequisites
- RBAC layer deployed (Layer 1) - `domains-terraform-role` exists
- Optionally, tfstate-backend layer deployed (Layer 2)
- Domain transferred to Route53 OR ready for new hosted zone creation
- AWS CLI configured
- Terraform 1.5+ installed

### Initial Deployment

1. **Navigate to domains layer**
   ```bash
   cd /workspace/domains
   ```

2. **Configure variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with AWS account ID and camdenwander.com
   ```

3. **Initialize Terraform (local state initially)**
   ```bash
   terraform init
   ```

4. **Plan infrastructure**
   ```bash
   terraform plan -out=tfplan
   # Review: Route53 zones, ACM certificates, DNS validation records
   ```

5. **Apply domains configuration**
   ```bash
   terraform apply tfplan
   ```

6. **Verify certificate validation** (wait 5-10 minutes for DNS propagation)
   ```bash
   terraform refresh
   terraform output certificate_statuses
   # Should show: "ISSUED" for all domains
   ```

7. **Verify name servers** (if domain was transferred)
   ```bash
   terraform output hosted_zone_name_servers
   # Compare with Route53 console or: dig NS camdenwander.com
   ```

8. **Optional: Migrate to remote state** (after tfstate-backend layer deployed)
   ```bash
   # Uncomment backend.tf
   terraform init -migrate-state
   ```

### Adding New Domains

1. Update `terraform.tfvars` - add domain to `domains` map
2. Run `terraform plan` - preview new zone and certificate
3. Apply changes
4. Verify certificate validation completes
5. Update name servers at registrar (if needed)
6. Proceed to `sites` layer to deploy website infrastructure

## Security Considerations

### Certificate Management
- Certificates are free via ACM when used with AWS services
- Automatic renewal handled by ACM (60 days before expiration)
- DNS validation is secure (no email validation vulnerabilities)
- Certificates issued to "Noise2Signal LLC" as registrant

### Route53 Security
- Hosted zones are not publicly listable (require zone ID to query)
- CAA records prevent unauthorized certificate issuance
- DNSSEC (optional enhancement) prevents DNS spoofing attacks
- Zone transfer disabled by default (AWS-managed zones)

### Access Control
- Only `domains-terraform-role` can modify zones/certificates
- GitHub Actions can assume role via OIDC (no long-lived credentials)
- State files encrypted in S3 (after migration)

### Domain Hijacking Prevention
- Registrar lock enabled (configure in Route53 console or via AWS CLI)
- Transfer lock enabled
- Contact privacy enabled (WHOIS protection)
- Multi-factor auth on AWS account

## Dependencies

### Upstream Dependencies
- `scp` layer (Layer 0) - Allows Route53 and ACM services
- `rbac` layer (Layer 1) - Provides `domains-terraform-role`
- `tfstate-backend` layer (Layer 2) - Optional, provides remote state backend

### Downstream Dependencies
- `sites` layer (Layer 4) - References zones and certificates via data sources

## Cost Estimates

**Per domain monthly costs**:
- Route53 hosted zone: $0.50/month
- Route53 queries: ~$0.40 per 1M queries (varies by traffic)
- ACM certificate: **Free** (when used with CloudFront)

**Total for 1 domain: ~$0.90/month + query costs**

**Scaling**: Each additional domain adds $0.50/month (zone) + query costs

## Testing & Validation

### Post-Deployment Checks
- [ ] Hosted zone exists for each domain
- [ ] Name servers are set correctly (if transferred)
- [ ] CAA records exist (if enabled)
- [ ] ACM certificate status is "ISSUED"
- [ ] DNS validation records exist in hosted zone
- [ ] Certificate covers apex + www subdomain (SANs)

### Validation Commands

```bash
# Check hosted zones
aws route53 list-hosted-zones | jq '.HostedZones[] | select(.Name == "camdenwander.com.")'

# Check certificate validation
aws acm describe-certificate \
  --certificate-arn $(terraform output -json certificate_arns | jq -r '.camdenwander.com') \
  --region us-east-1 \
  | jq -r '.Certificate.Status'
# Should output: ISSUED

# Test DNS resolution
dig NS camdenwander.com +short
dig CAA camdenwander.com +short

# Verify module outputs
terraform output hosted_zone_ids
terraform output certificate_arns
```

### Testing Data Source Discovery (From Sites Layer)

```bash
# In sites layer, verify domains can be discovered
cd /workspace/sites
terraform console

# Test zone discovery
> data.aws_route53_zone.site["camdenwander.com"].zone_id

# Test certificate discovery
> data.aws_acm_certificate.site["camdenwander.com"].arn
```

## Maintenance & Updates

### Regular Maintenance
- Monitor certificate expiration dates (ACM renews automatically, but verify)
- Review query logs if enabled (identify unusual traffic patterns)
- Audit CAA records annually
- Update DNS records when infrastructure changes (handled by sites layer)

### Certificate Renewal
- ACM handles renewal automatically 60 days before expiration
- Renewal uses same DNS validation records (no action required)
- If renewal fails, ACM sends email alerts to account contact
- Verify renewal occurred: `aws acm describe-certificate --certificate-arn <ARN> --region us-east-1`

### Adding/Removing Domains

**Adding**:
1. Ensure domain is transferred to Route53 or ready for new zone
2. Add to `domains` variable in `terraform.tfvars`
3. Apply changes
4. Verify certificate validation completes
5. Update sites layer to deploy website infrastructure

**Removing**:
1. First, destroy dependent resources in `sites` layer
2. Remove from `domains` variable in `terraform.tfvars`
3. Apply changes (zone and certificate will be destroyed)
4. Consider domain transfer out if no longer needed

## Troubleshooting

### Certificate Validation Stuck "Pending"

**Symptoms**: Certificate status remains "PENDING_VALIDATION" after 10+ minutes

**Causes**:
- DNS validation record not created correctly
- DNS propagation delay (usually <5 minutes, can be longer)
- Wrong hosted zone (validation record in wrong zone)

**Resolution**:
```bash
# Check validation records exist in Route53
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -json hosted_zone_ids | jq -r '.camdenwander.com') \
  | jq '.ResourceRecordSets[] | select(.Type == "CNAME") | select(.Name | contains("_acm-challenge"))'

# Manually verify DNS record resolves
dig _<random>.camdenwander.com CNAME +short

# Force refresh and reapply
terraform refresh
terraform apply
```

### Name Server Delegation Issues

**Symptoms**: DNS queries fail, domain not resolving

**Causes**:
- Name servers at registrar don't match Route53 zone
- Recent transfer, DNS propagation delay (24-48 hours)

**Resolution**:
```bash
# Get correct name servers from Route53
terraform output hosted_zone_name_servers

# Compare with registrar settings
# Update registrar to use Route53 name servers if mismatched

# Verify delegation
dig NS camdenwander.com @8.8.8.8
```

### Module Not Found Error

**Symptoms**: "Module not found" or "Module path does not exist"

**Causes**:
- Incorrect module source path
- Module directory doesn't exist

**Resolution**:
```bash
# Verify module exists
ls -la /workspace/modules/domain/

# Check module source in main.tf
grep "source" main.tf
# Should be: source = "../modules/domain"

# Re-initialize
terraform init
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
  | jq '.CertificateSummaryList[] | select(.DomainName == "camdenwander.com")'

# Import existing certificate if needed
terraform import 'module.domain["camdenwander.com"].aws_acm_certificate.this' <ARN>
```

## Future Enhancements

- DNSSEC configuration for enhanced security
- Route53 query logging to CloudWatch (traffic analysis)
- Automated domain renewal monitoring (alert before expiration)
- Multi-region certificate provisioning (if needed for regional services)
- Terraform remote state data sources (replace AWS data source pattern)

## References

- [Route53 Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html)
- [ACM Certificate Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [CAA Records](https://docs.aws.amazon.com/acm/latest/userguide/setup-caa.html)
- [Route53 DNSSEC](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec.html)
- [Terraform Module Sources](https://www.terraform.io/docs/language/modules/sources.html)
