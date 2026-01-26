# Static Site Module - S3 + CloudFront + DNS

## Module Purpose

This reusable module provisions complete **static website infrastructure** for a single domain, including S3 storage buckets, CloudFront CDN distribution, Origin Access Control, and Route53 DNS records. It creates a production-ready, secure static site with HTTPS and CDN caching.

**Module Type**: Reusable, extensible component

**Consumed By**: `sites` layer (Layer 4)

## Module Scope

### Creates
✅ S3 bucket for primary content (apex domain)
✅ S3 bucket for www redirect
✅ CloudFront Origin Access Control (OAC)
✅ CloudFront distribution with security headers
✅ S3 bucket policies for CloudFront access
✅ Route53 A/AAAA DNS records (apex + www)
✅ Complete website infrastructure isolation per site

### Requires
- Domain name (input variable)
- Hosted zone ID (from domains layer via data source)
- ACM certificate ARN (from domains layer via data source)
- AWS provider with S3/CloudFront/Route53 permissions

### Outputs
- S3 bucket names (for content upload)
- CloudFront distribution ID (for cache invalidation)
- CloudFront domain name
- Site HTTPS URL

## Module File Structure

```
/workspace/modules/static-site/
├── CLAUDE.md           # This file
├── main.tf             # S3, CloudFront, Route53 resources
├── variables.tf        # Input variables
├── outputs.tf          # Output values
└── versions.tf         # Provider version constraints
```

## Resources Managed

### 1. S3 Primary Content Bucket

Stores static website files (HTML, CSS, JS, images).

```hcl
# main.tf
resource "aws_s3_bucket" "primary" {
  bucket = var.domain_name  # e.g., camdenwander.com

  tags = merge(
    var.tags,
    {
      Domain  = var.domain_name
      Purpose = "static-site-content"
    }
  )
}

# Versioning (rollback capability)
resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access (use CloudFront OAC instead)
resource "aws_s3_bucket_public_access_block" "primary" {
  bucket = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Website configuration (for S3 website hosting behavior)
resource "aws_s3_bucket_website_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }
}
```

### 2. S3 WWW Redirect Bucket

Redirects www subdomain to apex domain (or vice versa).

```hcl
resource "aws_s3_bucket" "redirect" {
  bucket = "www.${var.domain_name}"

  tags = merge(
    var.tags,
    {
      Domain  = var.domain_name
      Purpose = "www-redirect"
    }
  )
}

resource "aws_s3_bucket_website_configuration" "redirect" {
  bucket = aws_s3_bucket.redirect.id

  redirect_all_requests_to {
    host_name = var.domain_name
    protocol  = "https"
  }
}

# Block public access for redirect bucket too
resource "aws_s3_bucket_public_access_block" "redirect" {
  bucket = aws_s3_bucket.redirect.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### 3. CloudFront Origin Access Control (OAC)

Modern replacement for Origin Access Identity (OAI).

```hcl
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.domain_name}-oac"
  description                       = "OAC for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

### 4. S3 Bucket Policy (CloudFront Access)

Grants CloudFront distribution read access to S3 bucket via OAC.

```hcl
resource "aws_s3_bucket_policy" "primary" {
  bucket = aws_s3_bucket.primary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.primary.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_cloudfront_distribution.this]
}
```

### 5. CloudFront Distribution

CDN distribution with security headers and caching.

```hcl
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.index_document
  price_class         = var.cloudfront_price_class
  aliases             = [var.domain_name, "www.${var.domain_name}"]

  origin {
    domain_name              = aws_s3_bucket.primary.bucket_regional_domain_name
    origin_id                = "S3-${var.domain_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.domain_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Use AWS managed cache policy (CachingOptimized)
    cache_policy_id = var.cache_policy_id != "" ? var.cache_policy_id : data.aws_cloudfront_cache_policy.optimized.id

    # Attach security headers response policy
    response_headers_policy_id = var.enable_security_headers ? aws_cloudfront_response_headers_policy.security[0].id : null
  }

  # Custom error page handling (403 -> 404)
  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = var.error_page_path
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = var.error_page_path
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(
    var.tags,
    {
      Domain = var.domain_name
    }
  )
}

# AWS managed cache policy lookup
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}
```

### 6. CloudFront Security Headers Policy

Enforces security headers on all responses.

```hcl
resource "aws_cloudfront_response_headers_policy" "security" {
  count = var.enable_security_headers ? 1 : 0

  name = "${replace(var.domain_name, ".", "-")}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000  # 2 years
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true  # X-Content-Type-Options: nosniff
    }

    frame_options {
      frame_option = "DENY"  # X-Frame-Options: DENY
      override     = true
    }

    xss_protection {
      mode_block = true  # X-XSS-Protection: 1; mode=block
      protection = true
      override   = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}
```

### 7. Route53 DNS Records

A/AAAA alias records pointing to CloudFront distribution.

```hcl
# Apex domain A record (IPv4)
resource "aws_route53_record" "apex_a" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# Apex domain AAAA record (IPv6)
resource "aws_route53_record" "apex_aaaa" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW subdomain A record
resource "aws_route53_record" "www_a" {
  zone_id = var.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW subdomain AAAA record
resource "aws_route53_record" "www_aaaa" {
  zone_id = var.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
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

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID (from domains layer)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN in us-east-1 (from domains layer)"
  type        = string
}

variable "project_name" {
  description = "Human-readable project name for tagging"
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "index_document" {
  description = "Index document for website hosting"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for website hosting"
  type        = string
  default     = "404.html"
}

variable "error_page_path" {
  description = "Path to custom error page (for CloudFront custom error responses)"
  type        = string
  default     = "/404.html"
}

variable "enable_versioning" {
  description = "Enable S3 versioning for content bucket"
  type        = bool
  default     = true
}

variable "enable_security_headers" {
  description = "Enable CloudFront security headers response policy"
  type        = bool
  default     = true
}

variable "cache_policy_id" {
  description = "Custom CloudFront cache policy ID (uses Managed-CachingOptimized if not specified)"
  type        = string
  default     = ""
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
output "s3_bucket_id" {
  description = "Primary S3 bucket name (for content upload)"
  value       = aws_s3_bucket.primary.id
}

output "s3_bucket_arn" {
  description = "Primary S3 bucket ARN"
  value       = aws_s3_bucket.primary.arn
}

output "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.primary.bucket_regional_domain_name
}

output "s3_redirect_bucket_id" {
  description = "WWW redirect S3 bucket name"
  value       = aws_s3_bucket.redirect.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "site_url" {
  description = "HTTPS URL of the site"
  value       = "https://${var.domain_name}"
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
    }
  }
}
```

## Usage Example (From Sites Layer)

```hcl
# /workspace/sites/main.tf

# Discover hosted zone from domains layer
data "aws_route53_zone" "site" {
  for_each = var.sites

  name         = each.key
  private_zone = false
}

# Discover ACM certificate from domains layer
data "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  for_each = var.sites

  domain      = each.key
  statuses    = ["ISSUED"]
  most_recent = true
}

# Create static site infrastructure
module "site" {
  source = "../modules/static-site"

  for_each = var.sites

  domain_name            = each.key
  hosted_zone_id         = data.aws_route53_zone.site[each.key].zone_id
  certificate_arn        = data.aws_acm_certificate.site[each.key].arn
  project_name           = each.value.project_name
  cloudfront_price_class = each.value.price_class
  error_page_path        = each.value.error_page_path

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Layer       = "4-sites"
    Project     = each.value.project_name
  }
}

# Access outputs
output "camdenwander_bucket" {
  value = module.site["camdenwander.com"].s3_bucket_id
}

output "camdenwander_distribution_id" {
  value = module.site["camdenwander.com"].cloudfront_distribution_id
}
```

## Module Design Decisions

### Why Separate Primary and Redirect Buckets?

**Rationale**: CloudFront can't handle S3 website redirects directly. Need separate bucket configured for redirect.

**Alternative**: Use Lambda@Edge for redirects (more complex, costs more).

### Why Origin Access Control (OAC)?

**Modern Standard**: OAC replaces deprecated Origin Access Identity (OAI).

**Benefits**:
- Better security (SigV4 signing)
- Works with S3 bucket policies (not ACLs)
- AWS recommended approach

### Why Block S3 Public Access?

**Security**: Content should ONLY be accessible via CloudFront (with HTTPS, security headers, CDN caching).

**Direct S3 Access**: Bypasses CloudFront features and costs more (no CDN caching).

### Why Security Headers Policy?

**Best Practice**: OWASP recommended security headers protect against common web vulnerabilities.

**Headers Included**:
- **HSTS**: Enforces HTTPS
- **X-Content-Type-Options**: Prevents MIME sniffing
- **X-Frame-Options**: Prevents clickjacking
- **X-XSS-Protection**: Browser XSS filter
- **Referrer-Policy**: Controls referrer information

### Why PriceClass_100 Default?

**Cost vs Coverage**: PriceClass_100 covers US, Canada, and Europe (where most traffic typically originates).

**Savings**: ~50% cheaper than PriceClass_All (global).

**Override**: Can be changed per site if global coverage needed.

## Module Behavior

### On First Apply

1. Creates S3 buckets (primary + redirect)
2. Creates CloudFront OAC
3. Creates CloudFront distribution (~15-30 minutes)
4. Creates S3 bucket policies
5. Creates Route53 DNS records
6. Creates security headers policy (if enabled)
7. Outputs bucket names and distribution ID

### On Subsequent Applies

- No changes (resources are idempotent)
- CloudFront config changes trigger redeployment (~15-30 minutes)

### On Destroy

1. Deletes Route53 records
2. Deletes CloudFront distribution (must wait for disable + delete, ~15 minutes)
3. Empties and deletes S3 buckets (if versioning enabled, must manually delete versions first)
4. Deletes OAC and policies

**Important**: Must empty S3 buckets before destroying (Terraform won't do this automatically).

## Validation & Testing

### Post-Deployment Checks

```bash
# Check S3 buckets
aws s3 ls s3://camdenwander.com/
aws s3 ls s3://www.camdenwander.com/

# Check CloudFront distribution status
aws cloudfront get-distribution \
  --id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camdenwander.com"]') \
  | jq -r '.Distribution.Status'
# Should output: Deployed

# Test HTTPS
curl -I https://camdenwander.com
curl -I https://www.camdenwander.com

# Test security headers
curl -I https://camdenwander.com | grep -i "strict-transport-security"

# Test DNS records
dig camdenwander.com A +short
dig www.camdenwander.com A +short
```

### Content Upload Test

```bash
# Upload test content
echo "<h1>Test Site</h1>" > index.html
echo "<h1>Not Found</h1>" > 404.html

aws s3 cp index.html s3://camdenwander.com/
aws s3 cp 404.html s3://camdenwander.com/

# Wait for CloudFront or invalidate cache
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*"

# Test site
curl https://camdenwander.com
# Should output: <h1>Test Site</h1>
```

## Troubleshooting

### S3 Bucket Already Exists

**Symptoms**: "BucketAlreadyExists" error during apply

**Causes**:
- Bucket name is globally taken (S3 buckets are globally unique)
- Previous deployment not fully destroyed

**Resolution**:
```bash
# Check if bucket exists
aws s3 ls s3://camdenwander.com

# If yours, import into state
terraform import 'module.site["camdenwander.com"].aws_s3_bucket.primary' camdenwander.com

# If not yours, choose different domain name
```

### CloudFront 403 Errors

**Symptoms**: Website returns 403 Forbidden

**Causes**:
- S3 bucket policy not applied yet (timing issue)
- Bucket is empty (no index.html)
- OAC not properly configured

**Resolution**:
```bash
# Verify bucket policy
aws s3api get-bucket-policy --bucket camdenwander.com | jq -r '.Policy | fromjson'

# Verify files exist
aws s3 ls s3://camdenwander.com/index.html

# Force bucket policy reapply
terraform taint 'module.site["camdenwander.com"].aws_s3_bucket_policy.primary'
terraform apply
```

### DNS Not Resolving

**Symptoms**: Domain doesn't resolve or resolves to wrong IP

**Causes**:
- DNS propagation delay (up to 48 hours, usually minutes)
- Route53 records not created
- Hosted zone not authoritative

**Resolution**:
```bash
# Check Route53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  | jq '.ResourceRecordSets[] | select(.Name | contains("camdenwander.com"))'

# Test direct DNS query
dig @8.8.8.8 camdenwander.com A
```

### Certificate Mismatch

**Symptoms**: CloudFront returns certificate errors

**Causes**:
- Certificate not in us-east-1
- Certificate doesn't cover domain (apex + www)
- Certificate not yet validated (PENDING_VALIDATION)

**Resolution**:
```bash
# Verify certificate details
aws acm describe-certificate \
  --certificate-arn <CERT_ARN> \
  --region us-east-1 \
  | jq '.Certificate | {Status, DomainName, SubjectAlternativeNames}'
```

## Module Extension Ideas

### Add Custom Domain for CloudFront Logging

Enable access logging to separate S3 bucket:

```hcl
# variables.tf
variable "enable_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = false
}

variable "logging_bucket" {
  description = "S3 bucket for CloudFront access logs"
  type        = string
  default     = ""
}

# main.tf
resource "aws_cloudfront_distribution" "this" {
  # ...

  dynamic "logging_config" {
    for_each = var.enable_logging ? [1] : []

    content {
      bucket = var.logging_bucket
      prefix = "${var.domain_name}/"
    }
  }
}
```

### Add WAF Integration

Attach AWS WAF for DDoS protection:

```hcl
# variables.tf
variable "waf_acl_id" {
  description = "AWS WAF Web ACL ID (if WAF protection enabled)"
  type        = string
  default     = ""
}

# main.tf
resource "aws_cloudfront_distribution" "this" {
  # ...
  web_acl_id = var.waf_acl_id
}
```

### Add Lambda@Edge Support

Attach Lambda functions for edge processing:

```hcl
# variables.tf
variable "lambda_function_associations" {
  description = "Lambda@Edge function associations"
  type = list(object({
    event_type   = string
    lambda_arn   = string
    include_body = bool
  }))
  default = []
}

# main.tf
resource "aws_cloudfront_distribution" "this" {
  default_cache_behavior {
    # ...

    dynamic "lambda_function_association" {
      for_each = var.lambda_function_associations

      content {
        event_type   = lambda_function_association.value.event_type
        lambda_arn   = lambda_function_association.value.lambda_arn
        include_body = lambda_function_association.value.include_body
      }
    }
  }
}
```

## Security Considerations

### S3 Bucket Security

- **No public access**: All 4 public access block settings enabled
- **Encryption at rest**: AES256 on all objects
- **Versioning**: Enabled for rollback and audit trail
- **Access control**: Only CloudFront can read (via OAC)

### CloudFront Security

- **HTTPS enforced**: HTTP redirects to HTTPS
- **TLS 1.2+**: Modern protocol only
- **Security headers**: HSTS, CSP, X-Frame-Options
- **IPv6 enabled**: No security downside, broader reach
- **OAC signing**: SigV4 authenticated requests to S3

### DNS Security

- **Alias records**: More secure than CNAME (no extra DNS lookup)
- **DNSSEC**: Can be enabled in domains layer for additional protection

## Cost Estimates

**Per module invocation (per site, low traffic)**:
- S3 storage: ~$0.023/GB (minimal for static sites)
- S3 requests: ~$0.005 per 1K requests
- CloudFront data transfer: ~$0.085/GB (PriceClass_100)
- CloudFront requests: ~$0.0075 per 10K HTTPS requests
- Route53 queries: Covered by domains layer

**Estimated monthly cost (10GB transfer, 100K requests)**: ~$1.50/month

## References

- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [CloudFront Security Headers](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-response-headers.html)
- [OWASP Secure Headers](https://owasp.org/www-project-secure-headers/)
- [Terraform AWS CloudFront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)
