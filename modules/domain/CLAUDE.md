# Domain Module - Route53 + ACM

## Module Purpose

This reusable module provisions **Route53 hosted zones** and **ACM SSL/TLS certificates** for a single domain. It handles DNS zone creation, certificate request, DNS validation, and optional CAA records.

**Module Type**: Reusable, extensible component

**Consumed By**: `domains` layer (Layer 3)

## Module Scope

### Creates
✅ Route53 hosted zone for the domain
✅ ACM certificate with DNS validation (us-east-1 for CloudFront)
✅ DNS validation records in Route53
✅ Certificate validation wait resource
✅ Optional CAA records (certificate authority authorization)

### Requires
- Domain name (input variable)
- AWS provider with Route53 permissions
- AWS provider aliased to `us_east_1` for ACM

### Outputs
- Hosted zone ID
- Name servers for registrar configuration
- ACM certificate ARN
- Certificate validation status

## Module File Structure

```
/workspace/modules/domain/
├── CLAUDE.md           # This file
├── main.tf             # Route53 and ACM resources
├── variables.tf        # Input variables
├── outputs.tf          # Output values
└── versions.tf         # Provider version constraints
```

## Resources Managed

### 1. Route53 Hosted Zone

```hcl
# main.tf
resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "Managed by Terraform - Noise2Signal LLC"

  tags = merge(
    var.tags,
    {
      Domain = var.domain_name
    }
  )
}
```

### 2. CAA Records (Optional)

Restrict certificate issuance to specified certificate authorities.

```hcl
resource "aws_route53_record" "caa" {
  count = var.enable_caa_records ? 1 : 0

  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 300

  records = [
    for issuer in var.caa_issuers : "0 issue \"${issuer}\""
  ]
}
```

### 3. ACM Certificate (us-east-1)

**Critical**: Must be created in us-east-1 for CloudFront compatibility.

```hcl
resource "aws_acm_certificate" "this" {
  provider = aws.us_east_1  # Explicit provider for us-east-1

  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Domain = var.domain_name
    }
  )
}
```

**Subject Alternative Names (SANs)**:
- Apex domain: `camdenwander.com`
- WWW subdomain: `www.camdenwander.com`

### 4. ACM DNS Validation Records

Automatically creates validation CNAMEs in Route53.

```hcl
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}
```

### 5. Certificate Validation Wait

Ensures certificate is fully validated before downstream resources use it.

```hcl
resource "aws_acm_certificate_validation" "this" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```

## Input Variables

```hcl
# variables.tf
variable "domain_name" {
  description = "Primary domain name (apex domain, e.g., camdenwander.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain must be a valid DNS name (lowercase, no www prefix)."
  }
}

variable "enable_caa_records" {
  description = "Enable CAA records to restrict certificate issuance"
  type        = bool
  default     = true
}

variable "caa_issuers" {
  description = "List of certificate authorities allowed to issue certificates (e.g., ['amazon.com'])"
  type        = list(string)
  default     = ["amazon.com"]
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
```

## Output Values

```hcl
# outputs.tf
output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.this.zone_id
}

output "hosted_zone_name_servers" {
  description = "List of name servers for the hosted zone (configure at registrar)"
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "ACM certificate ARN (us-east-1, for CloudFront)"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "certificate_status" {
  description = "ACM certificate validation status"
  value       = aws_acm_certificate.this.status
}

output "certificate_domain_name" {
  description = "ACM certificate domain name"
  value       = aws_acm_certificate.this.domain_name
}

output "certificate_sans" {
  description = "ACM certificate subject alternative names"
  value       = aws_acm_certificate.this.subject_alternative_names
}
```

## Provider Requirements

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
```

**Note**: This module requires a provider alias `aws.us_east_1` for ACM certificate creation.

## Usage Example (From Domains Layer)

```hcl
# /workspace/domains/main.tf
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

  # Pass us-east-1 provider alias
  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

# Access outputs
output "camdenwander_zone_id" {
  value = module.domain["camdenwander.com"].hosted_zone_id
}

output "camdenwander_cert_arn" {
  value = module.domain["camdenwander.com"].certificate_arn
}
```

## Module Design Decisions

### Why Apex + WWW in One Module?

**Rationale**: Most static sites use both apex and www subdomain (one as primary, one as redirect). Bundling them in the certificate SANs simplifies configuration.

**Alternative**: If you need more subdomains (e.g., `blog.camdenwander.com`), extend `subject_alternative_names` via variable.

### Why DNS Validation?

**Benefits**:
- More secure than email validation (no inbox compromise risk)
- Automatic renewal uses same DNS records (no manual intervention)
- Faster validation (minutes vs hours)

**Requirements**:
- Domain's hosted zone must be in Route53
- Terraform must have Route53 write permissions

### Why us-east-1 for ACM?

**CloudFront Requirement**: ACM certificates used with CloudFront distributions MUST be provisioned in `us-east-1` region.

**Global Service**: CloudFront is a global service, but certificate lookup is region-specific.

### Why Certificate Validation Wait?

**Prevents Errors**: Ensures certificate status is "ISSUED" before downstream resources (CloudFront) try to reference it.

**Terraform Behavior**: Without this, CloudFront creation may fail if attempted before certificate validation completes.

## Module Behavior

### On First Apply

1. Creates Route53 hosted zone
2. Optionally creates CAA records
3. Requests ACM certificate with DNS validation
4. Creates DNS validation records in Route53
5. Waits for certificate validation (~5-10 minutes)
6. Outputs zone ID and certificate ARN

### On Subsequent Applies

- No changes (resources are idempotent)
- ACM handles certificate renewal automatically (60 days before expiration)

### On Destroy

1. Deletes certificate validation records
2. Deletes ACM certificate (if not in use by CloudFront - will error if attached)
3. Deletes CAA records
4. Deletes hosted zone (if no records besides NS/SOA)

**Important**: Must destroy sites layer resources first (CloudFront must not reference certificate).

## Validation & Testing

### Post-Deployment Checks

```bash
# Check hosted zone
terraform state show 'module.domain["camdenwander.com"].aws_route53_zone.this'

# Check certificate status (should be ISSUED)
aws acm describe-certificate \
  --certificate-arn $(terraform output -json certificate_arns | jq -r '.["camdenwander.com"]') \
  --region us-east-1 \
  | jq -r '.Certificate.Status'

# Verify name servers
dig NS camdenwander.com +short

# Verify CAA records
dig CAA camdenwander.com +short
```

### Manual Testing

```bash
# Initialize module in isolation (for testing)
cd /workspace/modules/domain

# Create test configuration
cat > test.tf <<EOF
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "test_domain" {
  source = "./"

  domain_name        = "test-example.com"
  enable_caa_records = true
  caa_issuers        = ["amazon.com"]

  tags = {
    Environment = "test"
  }

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

output "zone_id" {
  value = module.test_domain.hosted_zone_id
}

output "cert_arn" {
  value = module.test_domain.certificate_arn
}
EOF

terraform init
terraform plan
# terraform apply (only if testing in real AWS account)
```

## Troubleshooting

### Certificate Validation Stuck

**Symptoms**: `terraform apply` hangs at certificate validation

**Causes**:
- DNS validation record not resolving (DNS propagation delay)
- Validation record created in wrong zone
- Route53 hosted zone not authoritative for domain

**Resolution**:
```bash
# Check validation records exist
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  | jq '.ResourceRecordSets[] | select(.Type == "CNAME") | select(.Name | contains("_acm-challenge"))'

# Manually verify DNS resolution
dig _<random>.camdenwander.com CNAME +short

# If stuck, cancel and retry
# Ctrl+C to cancel apply
terraform apply  # Retry
```

### Provider Alias Not Found

**Symptoms**: "Provider configuration not present" error

**Causes**:
- Parent configuration didn't pass `providers` map to module
- Provider alias mismatch (e.g., `us-east-1` vs `us_east_1`)

**Resolution**:
```hcl
# In calling code (domains/main.tf)
module "domain" {
  source = "../modules/domain"
  # ...

  providers = {
    aws.us_east_1 = aws.us_east_1  # Must match alias in module
  }
}
```

### Certificate Already Exists

**Symptoms**: Terraform shows certificate recreation

**Causes**:
- Certificate manually created outside Terraform
- Certificate imported but not in module state

**Resolution**:
```bash
# Import existing certificate
terraform import 'module.domain["camdenwander.com"].aws_acm_certificate.this' <CERTIFICATE_ARN>
```

## Module Extension Ideas

### Add Additional Subdomains

Extend SANs to include more subdomains:

```hcl
# variables.tf
variable "additional_sans" {
  description = "Additional subject alternative names (e.g., ['blog.example.com'])"
  type        = list(string)
  default     = []
}

# main.tf
resource "aws_acm_certificate" "this" {
  # ...
  subject_alternative_names = concat(
    ["www.${var.domain_name}"],
    var.additional_sans
  )
}
```

### Add DNSSEC Support

Enable DNSSEC for enhanced security:

```hcl
# variables.tf
variable "enable_dnssec" {
  description = "Enable DNSSEC for hosted zone"
  type        = bool
  default     = false
}

# main.tf
resource "aws_route53_zone_dnssec" "this" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id = aws_route53_zone.this.zone_id
}
```

### Add Query Logging

Enable Route53 query logging to CloudWatch:

```hcl
# variables.tf
variable "enable_query_logging" {
  description = "Enable Route53 query logging"
  type        = bool
  default     = false
}

variable "query_log_group_arn" {
  description = "CloudWatch log group ARN for query logs"
  type        = string
  default     = null
}

# main.tf
resource "aws_route53_query_log" "this" {
  count = var.enable_query_logging ? 1 : 0

  cloudwatch_log_group_arn = var.query_log_group_arn
  zone_id                  = aws_route53_zone.this.zone_id
}
```

## Security Considerations

### CAA Records

**Recommendation**: Always enable CAA records in production.

**Why**: Prevents unauthorized certificate authorities from issuing certificates for your domain.

**Configuration**: Only allow `amazon.com` (AWS Certificate Manager).

### Certificate Lifecycle

**ACM Renewal**: Automatic, handled by AWS 60 days before expiration.

**No Action Required**: As long as Route53 zone exists and DNS validation records remain.

**Monitoring**: Set up CloudWatch alarm for certificate expiration (belt-and-suspenders approach).

### Zone Security

**Registrar Lock**: Enable transfer lock at registrar to prevent domain hijacking.

**DNSSEC**: Consider enabling for additional security (prevents DNS spoofing).

## Cost Estimates

**Per module invocation (per domain)**:
- Route53 hosted zone: $0.50/month
- Route53 queries: ~$0.40 per 1M queries (varies by traffic)
- ACM certificate: **Free** (when used with CloudFront)

**Total: ~$0.90/month per domain + query costs**

## References

- [Route53 Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html)
- [ACM DNS Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [CAA Records](https://docs.aws.amazon.com/acm/latest/userguide/setup-caa.html)
- [Terraform Module Sources](https://www.terraform.io/docs/language/modules/sources.html)
- [Provider Configuration in Modules](https://www.terraform.io/docs/language/modules/develop/providers.html)
