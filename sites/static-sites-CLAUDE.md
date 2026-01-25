# Terraform Static Sites - Website Infrastructure Layer

## Repository Purpose

This repository manages **website infrastructure** for Noise2Signal LLC's wholly-owned static sites. It provisions S3 storage, CloudFront CDN, and DNS records for serving static websites globally with high performance and security.

**GitHub Repository**: `terraform-static-sites`

## Scope & Responsibilities

### In Scope
✅ **S3 Buckets**
- Primary content bucket per site (apex domain bucket)
- Redirect bucket per site (www subdomain → apex redirect)
- Bucket policies for CloudFront Origin Access Control (OAC)
- Static website hosting configuration

✅ **CloudFront Distributions**
- CDN distribution per site (complete isolation)
- Origin Access Control (OAC) for S3
- SSL/TLS configuration with ACM certificates
- Security headers via response policies
- Custom error pages (404, 403 handling)
- Cache policies and behaviors

✅ **Route53 DNS Records**
- A records (IPv4 alias to CloudFront)
- AAAA records (IPv6 alias to CloudFront)
- CNAME records (www subdomain → CloudFront)

✅ **Site Configuration Management**
- Variable-driven multi-site deployment
- Per-site resource naming conventions
- Isolated infrastructure per domain

### Out of Scope
❌ Route53 hosted zones - managed in `terraform-dns-domains`
❌ ACM certificates - managed in `terraform-dns-domains`
❌ State backend - managed in `terraform-inception`
❌ IAM execution roles - managed in `terraform-inception`
❌ Website content deployment (HTML/CSS/JS files) - handled via CI/CD or manual upload

## Architecture Context

### Multi-Repo Strategy
This repo is **Tier 3** in a 3-tier architecture:

1. **Tier 1: terraform-inception**
   - Terraform harness (state backend, execution roles)

2. **Tier 2: terraform-dns-domains**
   - Domain ownership (Route53 zones, ACM certificates)

3. **Tier 3: terraform-static-sites** ← YOU ARE HERE
   - Website infrastructure (S3, CloudFront, Route53 records)

### Dependency Flow
```
terraform-inception (state backend)
        ↓
terraform-dns-domains (zones + certs)
        ↓
terraform-static-sites (discovers zones/certs, deploys sites)
```

### State File Location

```
s3://noise2signal-terraform-state/
└── noise2signal/
    ├── inception.tfstate
    ├── dns-domains.tfstate
    └── static-sites.tfstate         ← This repo's state
```

## Site Portfolio

### Current Sites (Wholly-Owned)
This repository manages infrastructure for Noise2Signal LLC's wholly-owned static websites:

1. **camden-wander.com** (initial/primary)
2. Site 2 (TBD)
3. Site 3 (TBD)
4. Site 4 (TBD)
5. Site 5 (TBD)

**Design Principle**: Complete isolation per site (separate S3, CloudFront, DNS records). This enables:
- Clear separation of client IP vs Noise2Signal IP
- Easy extraction to separate AWS account if needed
- Minimal blast radius for issues
- Per-site cost tracking via tags

### Site Onboarding Process

**Prerequisites:**
1. Domain hosted zone created in `terraform-dns-domains`
2. ACM certificate validated in `terraform-dns-domains`
3. Domain propagated and resolvable

**Terraform Steps:**
1. Add site to `sites` variable in `terraform.tfvars`
2. Run `terraform plan` to preview S3, CloudFront, Route53 changes
3. Apply changes
4. Upload website content to S3 bucket
5. Test site accessibility (apex + www)
6. Verify HTTPS redirect and 404 error page

## Resources Managed

### 1. S3 Primary Content Bucket

One bucket per site for storing static website files.

**Naming convention**: `{domain}` (e.g., `camden-wander.com`)

**Configuration:**
```hcl
resource "aws_s3_bucket" "site" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = each.value.domain

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Terraform   = "true"
    Domain      = each.value.domain
    Project     = each.value.project_name
  }
}

# Versioning (recommended for rollback)
resource "aws_s3_bucket_versioning" "site" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = aws_s3_bucket.site[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = aws_s3_bucket.site[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access (use CloudFront OAC instead)
resource "aws_s3_bucket_public_access_block" "site" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = aws_s3_bucket.site[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Website configuration
resource "aws_s3_bucket_website_configuration" "site" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = aws_s3_bucket.site[each.key].id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}
```

### 2. S3 WWW Redirect Bucket

One bucket per site to redirect www subdomain to apex domain.

**Naming convention**: `www.{domain}` (e.g., `www.camden-wander.com`)

**Configuration:**
```hcl
resource "aws_s3_bucket" "site_redirect" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = "www.${each.value.domain}"

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Terraform   = "true"
    Domain      = each.value.domain
    Purpose     = "www-redirect"
  }
}

resource "aws_s3_bucket_website_configuration" "site_redirect" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = aws_s3_bucket.site_redirect[each.key].id

  redirect_all_requests_to {
    host_name = each.value.domain
    protocol  = "https"
  }
}
```

### 3. CloudFront Origin Access Control (OAC)

Modern replacement for Origin Access Identity (OAI). One OAC per site.

**Configuration:**
```hcl
resource "aws_cloudfront_origin_access_control" "site" {
  for_each = { for site in var.sites : site.domain => site }

  name                              = "${each.value.domain}-oac"
  description                       = "OAC for ${each.value.domain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

### 4. S3 Bucket Policy (CloudFront OAC Access)

Grant CloudFront distribution read access to S3 bucket.

**Configuration:**
```hcl
resource "aws_s3_bucket_policy" "site" {
  for_each = { for site in var.sites : site.domain => site }

  bucket = aws_s3_bucket.site[each.key].id

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
        Resource = "${aws_s3_bucket.site[each.key].arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site[each.key].arn
          }
        }
      }
    ]
  })
}
```

### 5. CloudFront Distribution

One distribution per site (complete isolation).

**Configuration:**
```hcl
resource "aws_cloudfront_distribution" "site" {
  for_each = { for site in var.sites : site.domain => site }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class  # Default: PriceClass_100
  aliases             = [each.value.domain, "www.${each.value.domain}"]

  origin {
    domain_name              = aws_s3_bucket.site[each.key].bucket_regional_domain_name
    origin_id                = "S3-${each.value.domain}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site[each.key].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${each.value.domain}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.site[each.key].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Custom error pages
  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/404.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Terraform   = "true"
    Domain      = each.value.domain
    Project     = each.value.project_name
  }
}

# Security headers response policy (optional but recommended)
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "noise2signal-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    xss_protection {
      mode_block = true
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

### 6. Route53 DNS Records

A/AAAA records for apex domain, pointing to CloudFront distribution.

**Configuration:**
```hcl
# Apex domain A record (IPv4)
resource "aws_route53_record" "site_a" {
  for_each = { for site in var.sites : site.domain => site }

  zone_id = data.aws_route53_zone.site[each.key].zone_id
  name    = each.value.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.site[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

# Apex domain AAAA record (IPv6)
resource "aws_route53_record" "site_aaaa" {
  for_each = { for site in var.sites : site.domain => site }

  zone_id = data.aws_route53_zone.site[each.key].zone_id
  name    = each.value.domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.site[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW subdomain A record
resource "aws_route53_record" "site_www_a" {
  for_each = { for site in var.sites : site.domain => site }

  zone_id = data.aws_route53_zone.site[each.key].zone_id
  name    = "www.${each.value.domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.site[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW subdomain AAAA record
resource "aws_route53_record" "site_www_aaaa" {
  for_each = { for site in var.sites : site.domain => site }

  zone_id = data.aws_route53_zone.site[each.key].zone_id
  name    = "www.${each.value.domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.site[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}
```

## Data Sources (Cross-Repo References)

### Route53 Hosted Zone Lookup

Discovers hosted zones created by `terraform-dns-domains`:

```hcl
data "aws_route53_zone" "site" {
  for_each = { for site in var.sites : site.domain => site }

  name         = each.value.domain
  private_zone = false
}
```

### ACM Certificate Lookup

Discovers certificates created by `terraform-dns-domains`:

```hcl
data "aws_acm_certificate" "site" {
  provider = aws.us_east_1  # Certificates must be in us-east-1 for CloudFront

  for_each = { for site in var.sites : site.domain => site }

  domain      = each.value.domain
  statuses    = ["ISSUED"]
  most_recent = true
}
```

### CloudFront Managed Cache Policy

Use AWS-managed optimized cache policy:

```hcl
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}
```

## Terraform Configuration Standards

### Backend Configuration

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "noise2signal-terraform-state"
    key            = "noise2signal/static-sites.tfstate"
    region         = "us-east-1"
    dynamodb_table = "noise2signal-terraform-state-lock"
    encrypt        = true
  }
}
```

### Provider Configuration

Dual-region: default + us-east-1 for ACM certificate lookups.

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
      ManagedBy = "terraform-static-sites"
    }
  }
}

# ACM certificate data source requires us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Owner     = "Noise2Signal LLC"
      Terraform = "true"
      ManagedBy = "terraform-static-sites"
    }
  }
}
```

### Variables

```hcl
variable "aws_region" {
  description = "Primary AWS region for S3 buckets"
  type        = string
  default     = "us-east-1"
}

variable "sites" {
  description = "List of static sites to manage"
  type = list(object({
    domain       = string
    project_name = string
  }))

  validation {
    condition = alltrue([
      for site in var.sites : can(regex("^[a-z0-9-]+\\.[a-z]{2,}$", site.domain))
    ])
    error_message = "Domains must be valid DNS names (lowercase, no www prefix)."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_100"  # US, Canada, Europe

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}
```

**Example terraform.tfvars:**
```hcl
sites = [
  {
    domain       = "camden-wander.com"
    project_name = "camden-wander-site"
  },
  # Add additional sites as onboarded
]

cloudfront_price_class = "PriceClass_100"
```

### Outputs

```hcl
output "s3_bucket_names" {
  description = "Map of domain names to S3 bucket names"
  value = {
    for domain, bucket in aws_s3_bucket.site : domain => bucket.id
  }
}

output "cloudfront_distribution_ids" {
  description = "Map of domain names to CloudFront distribution IDs (for cache invalidation)"
  value = {
    for domain, dist in aws_cloudfront_distribution.site : domain => dist.id
  }
}

output "cloudfront_domain_names" {
  description = "Map of domain names to CloudFront distribution domain names"
  value = {
    for domain, dist in aws_cloudfront_distribution.site : domain => dist.domain_name
  }
}

output "site_urls" {
  description = "Map of domain names to HTTPS URLs"
  value = {
    for domain in keys(aws_cloudfront_distribution.site) : domain => "https://${domain}"
  }
}
```

## Deployment Process

### Prerequisites
- `terraform-inception` deployed (state backend exists)
- `terraform-dns-domains` deployed (zones + certificates exist)
- Domain DNS propagated and certificate validated
- AWS credentials configured (IAM role from inception)

### Initial Deployment

1. **Clone repository**
   ```bash
   git clone https://github.com/noise2signal/terraform-static-sites.git
   cd terraform-static-sites
   ```

2. **Configure sites**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars - add camden-wander.com initially
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Plan and review**
   ```bash
   terraform plan -out=tfplan
   # Review: S3 buckets, CloudFront, Route53 records
   ```

5. **Apply**
   ```bash
   terraform apply tfplan
   ```

6. **Wait for CloudFront deployment**
   ```bash
   # CloudFront distribution takes 15-30 minutes to deploy
   aws cloudfront wait distribution-deployed \
     --id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camden-wander.com"]')
   ```

7. **Upload website content**
   ```bash
   aws s3 sync ./website-content/ s3://camden-wander.com/ --delete
   ```

8. **Test site**
   ```bash
   curl -I https://camden-wander.com
   curl -I https://www.camden-wander.com
   # Both should return 200 OK
   ```

### Adding New Sites

1. Ensure domain exists in `terraform-dns-domains` (zone + certificate)
2. Add site to `sites` variable in `terraform.tfvars`
3. Run `terraform plan` - preview new infrastructure
4. Apply changes
5. Wait for CloudFront deployment
6. Upload website content to new S3 bucket
7. Test site accessibility

## Content Deployment

### Manual Upload
```bash
# Sync local files to S3
aws s3 sync ./build/ s3://camden-wander.com/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*"
```

### CI/CD Integration (GitHub Actions Example)
```yaml
name: Deploy Website

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Sync to S3
        run: |
          aws s3 sync ./build/ s3://camden-wander.com/ --delete

      - name: Invalidate CloudFront
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ secrets.CLOUDFRONT_DISTRIBUTION_ID }} \
            --paths "/*"
```

## Security Considerations

### S3 Security
- Buckets are NOT publicly accessible (OAC enforces CloudFront-only access)
- Public ACLs blocked (all 4 settings)
- Encryption at rest (AES256)
- Versioning enabled (rollback capability, accidental deletion protection)
- Bucket policies scope access to specific CloudFront distribution

### CloudFront Security
- HTTPS enforced (HTTP redirects to HTTPS)
- TLS 1.2+ only (modern browsers)
- Security headers enforced (HSTS, CSP, X-Frame-Options, etc.)
- IPv6 enabled (no security downside, broader accessibility)
- Origin Access Control (OAC) prevents direct S3 access

### DNS Security
- DNSSEC (optional, configured in `terraform-dns-domains`)
- Alias records (not CNAME for apex, avoids DNS resolution issues)

### Content Security
- No sensitive data in S3 buckets (public website content only)
- 404 page does not leak directory structure
- Error responses do not expose backend details

## Dependencies

### Upstream Dependencies
- `terraform-inception` - State backend and IAM roles (implicit)
- `terraform-dns-domains` - Hosted zones and ACM certificates (via data sources)

### Downstream Dependencies
- None (this is the top layer)

## Cost Estimates

**Per site monthly costs:**
- S3 storage: ~$0.023/GB (minimal for static sites)
- S3 requests: ~$0.005 per 1K requests
- CloudFront data transfer: ~$0.085/GB (PriceClass_100, first 10TB)
- CloudFront requests: ~$0.0075 per 10K HTTPS requests
- Route53 queries: Handled by `terraform-dns-domains` (included in zone cost)

**Estimated total per site: $1-5/month** (varies by traffic)

**For 5 sites: $5-25/month** (assuming moderate traffic)

## Testing & Validation

### Post-Deployment Checks
- [ ] S3 buckets created (primary + www redirect)
- [ ] CloudFront distribution deployed (status: Deployed)
- [ ] Route53 A/AAAA records pointing to CloudFront
- [ ] HTTPS works for apex domain
- [ ] HTTPS works for www subdomain
- [ ] HTTP redirects to HTTPS
- [ ] 404 error page displays correctly
- [ ] Security headers present (check with securityheaders.com)

### Validation Commands

```bash
# Check S3 bucket
aws s3 ls s3://camden-wander.com/

# Check CloudFront distribution status
aws cloudfront get-distribution \
  --id <DISTRIBUTION_ID> \
  | jq -r '.Distribution.Status'
# Should output: Deployed

# Test DNS resolution
dig camden-wander.com A +short
dig www.camden-wander.com A +short

# Test HTTPS
curl -I https://camden-wander.com
curl -I https://www.camden-wander.com

# Test HTTP redirect
curl -I http://camden-wander.com
# Should show: 301 Moved Permanently, Location: https://...

# Test security headers
curl -I https://camden-wander.com | grep -i "strict-transport-security"

# Test 404 page
curl -I https://camden-wander.com/nonexistent-page
# Should show: 404 Not Found
```

## Maintenance & Updates

### CloudFront Cache Invalidation
After updating website content:
```bash
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*"

# Or specific paths
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/index.html" "/css/*"
```

**Note**: First 1,000 invalidation paths per month are free, then $0.005 per path.

### S3 Bucket Cleanup (Old Versions)
If versioning accumulates old files:
```bash
# List versions
aws s3api list-object-versions --bucket camden-wander.com

# Delete old versions (use lifecycle policy or manual cleanup)
```

### CloudFront Distribution Updates
Changing CloudFront configuration (cache policies, origins, etc.) triggers redeployment (15-30 minutes).

### Adding/Removing Sites
**Adding:**
1. Ensure domain exists in `terraform-dns-domains`
2. Add to `sites` variable
3. Apply Terraform changes
4. Upload content

**Removing:**
1. Back up S3 content if needed
2. Remove from `sites` variable
3. Apply Terraform changes (destroys S3, CloudFront, DNS records)
4. Manually delete S3 bucket versions if versioning was enabled

## Troubleshooting

### CloudFront Returns 403 Forbidden
**Causes:**
- S3 bucket policy not configured correctly
- OAC not attached to distribution
- File doesn't exist in S3

**Resolution:**
```bash
# Verify bucket policy
aws s3api get-bucket-policy --bucket camden-wander.com

# Check OAC configuration
terraform state show aws_cloudfront_origin_access_control.site[\"camden-wander.com\"]

# Verify file exists
aws s3 ls s3://camden-wander.com/index.html
```

### DNS Not Resolving
**Causes:**
- Route53 records not created
- DNS propagation delay (up to 48 hours, usually minutes)
- Name servers at registrar don't match hosted zone

**Resolution:**
```bash
# Check Route53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  | grep -A5 camden-wander.com

# Test DNS resolution
dig camden-wander.com @8.8.8.8
```

### Certificate Errors
**Causes:**
- ACM certificate not found (check `terraform-dns-domains`)
- Certificate in wrong region (must be us-east-1)
- Domain name mismatch

**Resolution:**
```bash
# Verify certificate exists and is ISSUED
aws acm list-certificates --region us-east-1 \
  | jq -r '.CertificateSummaryList[] | select(.DomainName == "camden-wander.com")'

# Check data source discovery
terraform console
> data.aws_acm_certificate.site["camden-wander.com"].arn
```

### CloudFront Deployment Stuck
**Causes:**
- AWS internal issue (rare)
- Invalid configuration (certificate, origin, etc.)

**Resolution:**
```bash
# Check distribution status
aws cloudfront get-distribution --id <DISTRIBUTION_ID>

# If stuck, may need to destroy and recreate
terraform destroy -target=aws_cloudfront_distribution.site[\"camden-wander.com\"]
terraform apply
```

## Future Enhancements

- Lambda@Edge for advanced redirects or A/B testing
- CloudFront Functions for lightweight transformations
- WAF integration for DDoS protection (if needed)
- CloudWatch alarms for 4xx/5xx error rates
- S3 lifecycle policies for old content cleanup
- Multi-region S3 replication (disaster recovery)
- Terraform remote state outputs (replace data source pattern)

## References

- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [CloudFront Custom Error Pages](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/GeneratingCustomErrorResponses.html)
- [Security Headers Best Practices](https://owasp.org/www-project-secure-headers/)
