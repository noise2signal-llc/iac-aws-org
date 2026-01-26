# Whollyowned Account - Sites Layer (S3 + CloudFront + DNS)

## Purpose

The **sites layer** deploys complete website infrastructure for all wholly-owned domains in the **whollyowned account**. This layer creates S3 buckets for content storage, CloudFront distributions for global CDN delivery, and DNS records pointing to CloudFront.

**This is Layer 3** - the final layer deployed in the whollyowned account, after RBAC, tfstate-backend, and domains layers.

---

## Responsibilities

1. **Create S3 buckets** (primary bucket + www redirect bucket per site)
2. **Configure S3 bucket policies** (allow CloudFront Origin Access Control)
3. **Create CloudFront distributions** (global CDN with HTTPS)
4. **Configure Origin Access Control (OAC)** (secure S3 access from CloudFront)
5. **Create Route53 A/AAAA records** (point domain to CloudFront distribution)
6. **Configure security headers** (HSTS, X-Frame-Options, etc.)
7. **Output distribution IDs** (for content deployment and cache invalidation)

**Design Goal**: Deploy production-ready static website infrastructure with global CDN, HTTPS, and security best practices.

---

## Resources Created

### S3 Bucket (Primary, Per Site)

```hcl
# Use local module for each site
module "site_camdenwander_com" {
  source = "../../modules/static-site"

  domain_name     = "camdenwander.com"
  hosted_zone_id  = data.aws_route53_zone.camdenwander_com.zone_id
  certificate_arn = data.aws_acm_certificate.camdenwander_com.arn

  cloudfront_price_class = "PriceClass_100"  # US, Canada, Europe
  enable_ipv6            = true
  default_root_object    = "index.html"
  custom_error_responses = [
    {
      error_code            = 404
      response_code         = 404
      response_page_path    = "/404.html"
      error_caching_min_ttl = 300
    }
  ]

  tags = {
    Organization = "noise2signal-llc"
    Account      = "whollyowned"
    CostCenter   = "whollyowned"
    Environment  = "production"
    ManagedBy    = "terraform"
    Layer        = "sites"
    Domain       = "camdenwander.com"
  }
}
```

**Module creates**:
- S3 bucket: `camdenwander.com` (website content)
- S3 bucket: `www.camdenwander.com` (redirect to primary)
- CloudFront distribution (CDN with HTTPS)
- CloudFront Origin Access Control (OAC)
- Route53 A record (IPv4): `camdenwander.com` → CloudFront
- Route53 AAAA record (IPv6): `camdenwander.com` → CloudFront
- Route53 A/AAAA records: `www.camdenwander.com` → CloudFront (redirect distribution)

**Primary Bucket**: `camdenwander.com`
**Region**: `us-east-1`
**Encryption**: AES256 server-side encryption
**Public Access**: Blocked (only CloudFront can access via OAC)

### S3 Bucket (WWW Redirect, Per Site)

**WWW Redirect Bucket**: `www.camdenwander.com`

Configured to redirect all requests to `https://camdenwander.com`:

```hcl
resource "aws_s3_bucket_website_configuration" "www_redirect" {
  bucket = aws_s3_bucket.www_redirect.id

  redirect_all_requests_to {
    host_name = var.domain_name
    protocol  = "https"
  }
}
```

### CloudFront Distribution (Primary, Per Site)

```hcl
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = var.enable_ipv6
  default_root_object = var.default_root_object
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "S3-${var.domain_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  aliases = [
    var.domain_name,
  ]

  default_cache_behavior {
    target_origin_id       = "S3-${var.domain_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400   # 1 day
    max_ttl     = 31536000 # 1 year
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 300
  }

  # Security headers via response headers policy
  response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

  tags = merge(var.tags, {
    Domain = var.domain_name
  })
}
```

**HTTPS**: Required (HTTP redirects to HTTPS)
**TLS Version**: 1.2+ (TLSv1.2_2021 minimum)
**Compression**: Enabled (Gzip, Brotli)
**Caching**: 1 day default, 1 year max
**IPv6**: Enabled (if `enable_ipv6 = true`)

### CloudFront Origin Access Control (OAC)

```hcl
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.domain_name}-oac"
  description                       = "OAC for ${var.domain_name} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

**Purpose**: Securely grant CloudFront access to S3 bucket (replaces legacy Origin Access Identity).

**S3 Bucket Policy** (allows CloudFront OAC):

```hcl
data "aws_iam_policy_document" "cloudfront_oac" {
  statement {
    sid    = "AllowCloudFrontOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.this.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.cloudfront_oac.json
}
```

### CloudFront Security Headers Policy

```hcl
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.domain_name}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000  # 2 years
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

**Headers Added**:
- `Strict-Transport-Security`: max-age=63072000; includeSubDomains; preload
- `X-Content-Type-Options`: nosniff
- `X-Frame-Options`: DENY
- `X-XSS-Protection`: 1; mode=block
- `Referrer-Policy`: strict-origin-when-cross-origin

### Route53 DNS Records (Per Site)

```hcl
# A record (IPv4)
resource "aws_route53_record" "this_a" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# AAAA record (IPv6)
resource "aws_route53_record" "this_aaaa" {
  count   = var.enable_ipv6 ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW redirect (A and AAAA records)
resource "aws_route53_record" "www_redirect_a" {
  zone_id = var.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.www_redirect.domain_name
    zone_id                = aws_cloudfront_distribution.www_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}
```

**Result**: `camdenwander.com` and `www.camdenwander.com` both point to CloudFront distributions.

---

## Variables

### Required Variables

```hcl
variable "sites" {
  type = map(object({
    cloudfront_price_class = string
    enable_ipv6            = bool
    default_root_object    = string
    custom_error_responses = list(object({
      error_code            = number
      response_code         = number
      response_page_path    = string
      error_caching_min_ttl = number
    }))
  }))
  description = "Map of domain names to site configuration"
}
```

**Example** (in `terraform.tfvars`):

```hcl
sites = {
  "camdenwander.com" = {
    cloudfront_price_class = "PriceClass_100"  # US, Canada, Europe
    enable_ipv6            = true
    default_root_object    = "index.html"
    custom_error_responses = [
      {
        error_code            = 404
        response_code         = 404
        response_page_path    = "/404.html"
        error_caching_min_ttl = 300
      }
    ]
  }
  # Add more sites here as needed
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

### Per-Site Outputs

```hcl
output "s3_bucket_name_camdenwander_com" {
  value       = module.site_camdenwander_com.s3_bucket_name
  description = "S3 bucket name for camdenwander.com"
}

output "cloudfront_distribution_id_camdenwander_com" {
  value       = module.site_camdenwander_com.cloudfront_distribution_id
  description = "CloudFront distribution ID for camdenwander.com"
}

output "cloudfront_domain_name_camdenwander_com" {
  value       = module.site_camdenwander_com.cloudfront_domain_name
  description = "CloudFront distribution domain name"
}

output "website_url_camdenwander_com" {
  value       = "https://${module.site_camdenwander_com.domain_name}"
  description = "Website URL for camdenwander.com"
}
```

### Aggregated Outputs

```hcl
output "site_details" {
  value = {
    for domain, config in var.sites : domain => {
      s3_bucket_name         = module.site[domain].s3_bucket_name
      cloudfront_distribution_id = module.site[domain].cloudfront_distribution_id
      cloudfront_domain_name     = module.site[domain].cloudfront_domain_name
      website_url                = "https://${domain}"
    }
  }
  description = "Map of domain names to site details (S3 bucket, CloudFront distribution, URL)"
}
```

---

## Authentication & Permissions

### Deployment Authentication

**Authentication**: Assumes `sites-terraform-role` (via GitHub Actions) or SSO admin (manual)

**AWS CLI Profile Setup** (for SSO admin manual deployment):

```bash
export AWS_PROFILE=whollyowned-admin
aws sso login --profile whollyowned-admin
```

**Required Permissions** (via `sites-terraform-role` from RBAC layer):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:GetBucketWebsite",
        "s3:PutBucketWebsite",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::*.noise2signal.com",
        "arn:aws:s3:::*.noise2signal.com/*",
        "arn:aws:s3:::camdenwander.com",
        "arn:aws:s3:::camdenwander.com/*",
        "arn:aws:s3:::www.camdenwander.com",
        "arn:aws:s3:::www.camdenwander.com/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution",
        "cloudfront:DeleteDistribution",
        "cloudfront:GetDistribution",
        "cloudfront:UpdateDistribution",
        "cloudfront:ListDistributions",
        "cloudfront:CreateOriginAccessControl",
        "cloudfront:DeleteOriginAccessControl",
        "cloudfront:GetOriginAccessControl",
        "cloudfront:UpdateOriginAccessControl",
        "cloudfront:CreateResponseHeadersPolicy",
        "cloudfront:DeleteResponseHeadersPolicy",
        "cloudfront:GetResponseHeadersPolicy",
        "cloudfront:UpdateResponseHeadersPolicy",
        "cloudfront:CreateInvalidation",
        "cloudfront:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets",
        "route53:GetChange"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "acm:DescribeCertificate",
        "acm:ListCertificates",
        "acm:GetCertificate"
      ],
      "Resource": "*"
    }
  ]
}
```

**Provider Configuration**:

```hcl
# provider.tf
provider "aws" {
  region = "us-east-1"

  # Optional: Assume sites-terraform-role (for GitHub Actions)
  # assume_role {
  #   role_arn     = "arn:aws:iam::<WHOLLYOWNED_ACCOUNT_ID>:role/sites-terraform-role"
  #   session_name = "terraform-sites"
  # }
}

# ACM certificate lookup requires us-east-1 provider
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
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
#     key            = "whollyowned/sites.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "n2s-terraform-state-whollyowned-lock"
#     encrypt        = true
#   }
# }
```

### Remote State (After Layer 1)

After deploying `tfstate-backend` layer, uncomment `backend.tf` and migrate:

```bash
cd whollyowned/sites
terraform init -migrate-state
```

---

## Cross-Layer Dependencies

### Domains Layer → Sites Layer

**Sites layer discovers resources from domains layer** via AWS data sources (no remote state dependencies):

```hcl
# Discover hosted zone from domains layer
data "aws_route53_zone" "camdenwander_com" {
  name = "camdenwander.com"
}

# Discover ACM certificate from domains layer
data "aws_acm_certificate" "camdenwander_com" {
  provider    = aws.us_east_1
  domain      = "camdenwander.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

# Use in module
module "site_camdenwander_com" {
  source = "../../modules/static-site"

  domain_name     = "camdenwander.com"
  hosted_zone_id  = data.aws_route53_zone.camdenwander_com.zone_id
  certificate_arn = data.aws_acm_certificate.camdenwander_com.arn
  # ...
}
```

**Design Rationale**: Simpler than remote state lookups, more reliable (AWS data sources are well-tested).

---

## Deployment

### Prerequisites

1. RBAC layer deployed (IAM roles exist)
2. Tfstate-backend layer deployed (optional, for remote state)
3. Domains layer deployed (hosted zones + ACM certificates exist)
4. **ACM certificates validated** (status: "ISSUED", not "Pending Validation")
5. AWS CLI configured with whollyowned SSO profile

### Step 1: Create terraform.tfvars

```hcl
# whollyowned/sites/terraform.tfvars
sites = {
  "camdenwander.com" = {
    cloudfront_price_class = "PriceClass_100"  # US, Canada, Europe
    enable_ipv6            = true
    default_root_object    = "index.html"
    custom_error_responses = [
      {
        error_code            = 404
        response_code         = 404
        response_page_path    = "/404.html"
        error_caching_min_ttl = 300
      }
    ]
  }
  # Add more sites as needed
}
```

### Step 2: Initialize Terraform

```bash
cd whollyowned/sites
terraform init
```

### Step 3: Review Plan

```bash
terraform plan
```

**Expected Resources (per site)**:
- 2 S3 buckets (primary + www redirect)
- 2 S3 bucket policies
- 2 S3 bucket encryption configurations
- 2 S3 bucket public access blocks
- 1 S3 bucket website configuration (www redirect)
- 2 CloudFront distributions (primary + www redirect)
- 2 CloudFront Origin Access Controls
- 1 CloudFront response headers policy
- 4 Route53 records (A + AAAA for primary, A + AAAA for www redirect)

**Total per site**: ~17 resources

### Step 4: Apply

```bash
terraform apply
```

**Timeline**: ~20-30 minutes (CloudFront distribution deployment is slow)

**Note**: CloudFront distributions take 15-30 minutes to fully deploy and propagate globally.

### Step 5: Verify Resources

```bash
# Verify S3 buckets
aws s3 ls --profile whollyowned-admin | grep camdenwander
# Expected: camdenwander.com, www.camdenwander.com

# Verify CloudFront distributions
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='camdenwander.com'].{ID:Id,Status:Status,DomainName:DomainName}" \
  --profile whollyowned-admin
# Expected: Status "Deployed"

# Verify DNS records
ZONE_ID=$(terraform output -raw hosted_zone_id_camdenwander_com 2>/dev/null || \
  aws route53 list-hosted-zones --query "HostedZones[?Name=='camdenwander.com.'].Id | [0]" --output text --profile whollyowned-admin | cut -d/ -f3)
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='A' || Type=='AAAA']" \
  --profile whollyowned-admin
# Expected: A and AAAA records pointing to CloudFront distributions
```

### Step 6: Upload Website Content

After CloudFront deployment completes:

```bash
# Sync website content to S3
S3_BUCKET=$(terraform output -raw s3_bucket_name_camdenwander_com)
aws s3 sync ./website/ s3://$S3_BUCKET/ --delete --profile whollyowned-admin

# Invalidate CloudFront cache (force refresh)
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id_camdenwander_com)
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*" \
  --profile whollyowned-admin
```

**Alternative** (direct bucket name):

```bash
aws s3 sync ./website/ s3://camdenwander.com/ --delete --profile whollyowned-admin
```

### Step 7: Test Website Access

```bash
# Test HTTPS access
curl -I https://camdenwander.com
# Expected: HTTP/2 200, x-cache header from CloudFront

# Test WWW redirect
curl -I https://www.camdenwander.com
# Expected: HTTP/2 301 redirect to https://camdenwander.com

# Test security headers
curl -I https://camdenwander.com | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options"
# Expected: HSTS, X-Frame-Options, X-Content-Type-Options headers present

# Open in browser
open https://camdenwander.com
```

---

## Post-Deployment Tasks

### 1. Verify CloudFront Distribution

```bash
# Get distribution status
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id_camdenwander_com)
aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query "Distribution.{Status:Status,DomainName:DomainName,Enabled:Enabled}" \
  --profile whollyowned-admin
```

**Expected Status**: `Deployed` (after 15-30 minutes)

### 2. Test Cache Behavior

```bash
# First request (cache miss)
curl -I https://camdenwander.com
# Expected: x-cache: Miss from cloudfront

# Second request (cache hit)
curl -I https://camdenwander.com
# Expected: x-cache: Hit from cloudfront
```

### 3. Enable CloudFront Logging (Optional)

Future enhancement: Enable access logs to S3 bucket for analytics.

### 4. Set Up Monitoring (Optional)

Future enhancement: CloudWatch alarms for 4xx/5xx error rates.

---

## Content Deployment Workflow

### Deploy Website Content (via AWS CLI)

```bash
# Sync local website directory to S3
aws s3 sync ./website/ s3://camdenwander.com/ --delete --profile whollyowned-admin

# Invalidate CloudFront cache (force CDN refresh)
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*" \
  --profile whollyowned-admin
```

**Options**:
- `--delete`: Remove files from S3 that don't exist locally
- `--dryrun`: Preview changes without actually syncing
- `--exclude "*.tmp"`: Exclude files matching pattern

### Deploy via GitHub Actions (Future)

```yaml
# .github/workflows/deploy-website.yml
name: Deploy Website Content

on:
  push:
    branches: [main]
    paths:
      - 'websites/camdenwander.com/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::WHOLLYOWNED_ACCOUNT_ID:role/sites-terraform-role
          aws-region: us-east-1

      - name: Sync to S3
        run: |
          aws s3 sync websites/camdenwander.com/ s3://camdenwander.com/ --delete

      - name: Invalidate CloudFront Cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id <DISTRIBUTION_ID> \
            --paths "/*"
```

---

## Adding a New Site

### Step 1: Ensure Domain Exists in Domains Layer

Verify domain exists in `domains` layer with validated certificate:

```bash
cd whollyowned/domains
terraform output certificate_status_newdomain_com
# Expected: "ISSUED"
```

If not, add domain to `domains` layer first and wait for certificate validation.

### Step 2: Add to terraform.tfvars

```hcl
# whollyowned/sites/terraform.tfvars
sites = {
  "camdenwander.com" = { ... },
  "newdomain.com" = {  # Added
    cloudfront_price_class = "PriceClass_100"
    enable_ipv6            = true
    default_root_object    = "index.html"
    custom_error_responses = [
      {
        error_code            = 404
        response_code         = 404
        response_page_path    = "/404.html"
        error_caching_min_ttl = 300
      }
    ]
  }
}
```

### Step 3: Apply Changes

```bash
cd whollyowned/sites
terraform apply
```

**Timeline**: ~20-30 minutes (CloudFront deployment)

### Step 4: Upload Content

```bash
aws s3 sync ./new-website/ s3://newdomain.com/ --delete --profile whollyowned-admin
```

---

## Troubleshooting

### CloudFront Distribution Creation Timeout

**Symptoms**: `terraform apply` times out during CloudFront distribution creation (>30 minutes)

**Cause**: CloudFront deployment is slow (normal), or API issue

**Resolution**:

1. Wait (CloudFront can take 30-45 minutes in rare cases)
2. Check CloudFront console for distribution status
3. If stuck, cancel Terraform and import distribution: `terraform import module.site_camdenwander_com.aws_cloudfront_distribution.this <DISTRIBUTION_ID>`

### Error: ACM Certificate Not Found

**Symptoms**: `terraform plan` fails with "ACM certificate not found for domain X"

**Cause**: Certificate not issued yet, or wrong domain name

**Resolution**:

```bash
# Check certificate status in domains layer
cd whollyowned/domains
terraform output certificate_status_camdenwander_com
# If "Pending Validation", wait for NS records to propagate (Phase 3)

# Verify certificate exists
aws acm list-certificates --region us-east-1 --profile whollyowned-admin
```

### CloudFront 403 Forbidden Errors

**Symptoms**: Website returns 403 Forbidden when accessing https://camdenwander.com

**Cause**: S3 bucket policy doesn't allow CloudFront OAC access, or bucket is empty

**Resolution**:

1. Verify S3 bucket policy includes CloudFront OAC:
   ```bash
   aws s3api get-bucket-policy --bucket camdenwander.com --profile whollyowned-admin
   ```
2. Verify S3 bucket has content:
   ```bash
   aws s3 ls s3://camdenwander.com/ --profile whollyowned-admin
   ```
3. If bucket is empty, upload `index.html` test file:
   ```bash
   echo "<h1>Test</h1>" > index.html
   aws s3 cp index.html s3://camdenwander.com/ --profile whollyowned-admin
   ```
4. Re-apply sites layer to fix bucket policy: `terraform apply`

### CloudFront 404 Not Found Errors

**Symptoms**: Website returns 404 for all pages except index.html

**Cause**: Missing files in S3 bucket, or incorrect `default_root_object`

**Resolution**:

1. Verify files exist in S3:
   ```bash
   aws s3 ls s3://camdenwander.com/ --recursive --profile whollyowned-admin
   ```
2. Check `default_root_object` in `terraform.tfvars` (should be `index.html`)
3. Verify custom error responses configured (404 → /404.html)

### DNS Not Resolving to CloudFront

**Symptoms**: `dig camdenwander.com` doesn't show CloudFront domain name

**Cause**: DNS records not created, or DNS propagation delay

**Resolution**:

```bash
# Verify Route53 records exist
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='camdenwander.com.'].Id | [0]" --output text --profile whollyowned-admin | cut -d/ -f3)
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='A']" \
  --profile whollyowned-admin

# If records missing, re-apply sites layer
cd whollyowned/sites
terraform apply
```

### HTTPS Certificate Errors in Browser

**Symptoms**: Browser shows "Invalid certificate" or "Certificate mismatch"

**Cause**: ACM certificate not issued, or CloudFront using wrong certificate

**Resolution**:

1. Verify certificate ARN in CloudFront distribution:
   ```bash
   DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id_camdenwander_com)
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query "Distribution.DistributionConfig.ViewerCertificate.ACMCertificateArn" \
     --profile whollyowned-admin
   ```
2. Verify certificate is issued and covers domain:
   ```bash
   CERT_ARN=$(terraform output -raw certificate_arn_camdenwander_com)
   aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --profile whollyowned-admin
   # Check Status: ISSUED, DomainName: camdenwander.com, SubjectAlternativeNames: *.camdenwander.com
   ```

---

## Cost Considerations

### S3 Costs

**Storage**: ~$0.023/GB per month (Standard tier)
- Typical small website: 10-100 MB
- Estimated monthly cost: <$0.01-0.05

**Requests**: ~$0.005 per 1,000 PUT requests, $0.0004 per 1,000 GET requests
- Most requests served by CloudFront (S3 requests minimized)
- Estimated monthly cost: <$0.01

**Total S3 cost per site**: ~$0.02-0.06/month

### CloudFront Costs

**Data Transfer Out**: ~$0.085/GB (PriceClass_100: US, Canada, Europe)
- Typical small website: 10 GB/month
- Estimated monthly cost: ~$0.85

**HTTPS Requests**: ~$0.0075 per 10,000 requests
- Typical small website: 100,000 requests/month
- Estimated monthly cost: ~$0.08

**Total CloudFront cost per site**: ~$0.93-5.00/month (traffic-dependent)

### Route53 Costs

**A/AAAA Records**: Included in hosted zone cost (see domains layer)
- No additional cost for DNS records

### Total Cost (Per Site)

```
S3 storage:              ~$0.02-0.06/month
CloudFront data transfer: ~$0.85/month (10 GB)
CloudFront requests:      ~$0.08/month (100K requests)
──────────────────────────────
Total per site:          ~$0.95-1.00/month (low traffic)
Total per site:          ~$3.00-5.00/month (medium traffic, 50 GB)
```

**Scaling**: Each additional site adds ~$1-5/month depending on traffic.

**Included in**: Whollyowned account cost allocation (CostCenter: whollyowned)

**Total for 1 site (domains + sites layers)**: ~$1.87-5.87/month

---

## Security Considerations

### Origin Access Control (OAC)

- **S3 buckets not public**: All public access blocked, only CloudFront can access via OAC
- **Bucket policy**: Restricts access to specific CloudFront distribution (via `aws:SourceArn` condition)
- **Replaces legacy OAI**: Origin Access Control is the modern, secure method

### HTTPS Enforcement

- **HTTP → HTTPS redirect**: `viewer_protocol_policy = "redirect-to-https"`
- **TLS 1.2+ minimum**: `minimum_protocol_version = "TLSv1.2_2021"`
- **SNI-only**: `ssl_support_method = "sni-only"` (saves cost, widely supported)

### Security Headers

Enforced via CloudFront response headers policy:
- **HSTS**: `max-age=63072000; includeSubDomains; preload` (2 years)
- **X-Content-Type-Options**: `nosniff` (prevent MIME sniffing)
- **X-Frame-Options**: `DENY` (prevent clickjacking)
- **X-XSS-Protection**: `1; mode=block` (legacy XSS protection)
- **Referrer-Policy**: `strict-origin-when-cross-origin` (privacy)

### Content Compression

- **Gzip/Brotli enabled**: `compress = true` (reduces bandwidth, improves performance)
- **Automatically compresses**: HTML, CSS, JS, JSON, XML, SVG

### Caching Strategy

- **Default TTL**: 1 day (86400 seconds)
- **Max TTL**: 1 year (31536000 seconds)
- **Query strings**: Not forwarded by default (reduces cache misses)
- **Invalidation**: Use `aws cloudfront create-invalidation` to force refresh

---

## References

### Related Layers

- [../CLAUDE.md](../CLAUDE.md) - Whollyowned account overview
- [../rbac/CLAUDE.md](../rbac/CLAUDE.md) - RBAC layer (creates IAM roles)
- [../tfstate-backend/CLAUDE.md](../tfstate-backend/CLAUDE.md) - State backend layer
- [../domains/CLAUDE.md](../domains/CLAUDE.md) - Domains layer (provides certificates)

### Module Documentation

- [../../modules/static-site/CLAUDE.md](../../modules/static-site/CLAUDE.md) - Static site module (S3 + CloudFront pattern)

### Parent Documentation

- [../../CLAUDE.md](../../CLAUDE.md) - Overall architecture

### AWS Documentation

- [CloudFront OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [CloudFront Security Headers](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-response-headers.html)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CloudFront Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/best-practices.html)

---

**Layer**: 3 (Sites)
**Account**: noise2signal-llc-whollyowned
**Last Updated**: 2026-01-26
