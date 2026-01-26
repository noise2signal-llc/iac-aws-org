# Layer 4: Sites (S3 + CloudFront + DNS)

## Layer Purpose

This layer manages **website infrastructure** for Noise2Signal LLC's static sites. It provisions S3 storage, CloudFront CDN distributions, and DNS records for serving static websites globally with high performance and security. Sites may use the reusable `static-site` module or direct resource definitions depending on configuration similarity.

**Deployment Order**: Layer 4 (deployed after domains layer)

## Scope & Responsibilities

### In Scope
✅ **S3 Buckets**
- Primary content bucket per site (apex domain bucket)
- Redirect bucket per site (www subdomain → apex redirect)
- Bucket policies for CloudFront Origin Access Control (OAC)
- Static website hosting configuration
- Versioning and encryption

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
- Both apex and www subdomain records

✅ **Site Configuration Management**
- Variable-driven multi-site deployment
- Per-site resource naming conventions
- Isolated infrastructure per domain

### Out of Scope
❌ Route53 hosted zones - managed in `domains` layer
❌ ACM certificates - managed in `domains` layer
❌ State backend - managed in `tfstate-backend` layer
❌ IAM roles - managed in `rbac` layer
❌ Website content deployment (HTML/CSS/JS files) - handled via CI/CD or manual upload

## Architecture Context

### Layer Dependencies

```
Layer 0: scp (service constraints)
    ↓
Layer 1: rbac (IAM roles)
    ↓
Layer 2: tfstate-backend (S3 + DynamoDB) [optional]
    ↓
Layer 3: domains (Route53 + ACM)
    ↓
Layer 4: sites (S3 + CloudFront + DNS) ← YOU ARE HERE
```

### State Management

**State Storage**: Local state file initially (`.tfstate` in this directory, gitignored)

**Backend Migration**: After `tfstate-backend` layer is deployed, uncomment `backend.tf` and run `terraform init -migrate-state`

**State Key**: `noise2signal/sites.tfstate` (in S3 after migration)

**Deployment Role**: `sites-terraform-role` (from RBAC layer)

## Site Portfolio

### Current Sites (Wholly-Owned)

This layer manages infrastructure for Noise2Signal LLC's wholly-owned static websites:

1. **camdenwander.com** (primary)
2. Additional sites TBD

**Design Principle**: Complete isolation per site (separate S3, CloudFront, DNS records). This enables:
- Clear separation of client IP vs Noise2Signal IP
- Easy extraction to separate AWS account if needed
- Minimal blast radius for issues
- Per-site cost tracking via tags

### Site Variable Structure

Sites can be defined as either:

**Option A: Map (for similar site configurations)**
```hcl
sites = {
  "camdenwander.com" = {
    project_name    = "Camden Wander Personal Site"
    price_class     = "PriceClass_100"
    error_page_path = "/404.html"
  }
}
```

**Option B: Individual module calls (for varied configurations)**
```hcl
# main.tf
module "camdenwander_site" {
  source = "../modules/static-site"

  domain_name = "camdenwander.com"
  # ... site-specific configuration
}

module "another_site" {
  source = "../modules/static-site"

  domain_name = "another.com"
  # ... different configuration
}
```

**Recommendation**: Start with map + `for_each` for consistency, migrate to individual modules if configurations diverge significantly.

## Module Integration (If Using Static-Site Module)

If site configurations are similar, use the `static-site` module (located in `/workspace/modules/static-site/`).

### Module Call Pattern

```hcl
# main.tf
module "site" {
  source = "../modules/static-site"

  for_each = var.sites

  domain_name        = each.key
  project_name       = each.value.project_name
  cloudfront_price_class = each.value.price_class
  error_page_path    = each.value.error_page_path

  # Discover hosted zone from domains layer
  hosted_zone_id = data.aws_route53_zone.site[each.key].zone_id

  # Discover ACM certificate from domains layer
  certificate_arn = data.aws_acm_certificate.site[each.key].arn

  tags = {
    Owner       = "Noise2Signal LLC"
    Environment = "production"
    Layer       = "4-sites"
    Project     = each.value.project_name
  }

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}
```

### Module Expected Outputs

The `static-site` module should expose:
- `s3_bucket_id` - Primary S3 bucket name (for content upload)
- `s3_bucket_arn` - S3 bucket ARN
- `cloudfront_distribution_id` - CloudFront distribution ID (for cache invalidation)
- `cloudfront_domain_name` - CloudFront domain name (for verification)
- `site_url` - HTTPS URL of the site

### Layer Outputs (Aggregated from Module)

```hcl
# outputs.tf
output "s3_bucket_names" {
  description = "Map of domain names to S3 bucket names"
  value = {
    for domain, site in module.site : domain => site.s3_bucket_id
  }
}

output "cloudfront_distribution_ids" {
  description = "Map of domain names to CloudFront distribution IDs (for cache invalidation)"
  value = {
    for domain, site in module.site : domain => site.cloudfront_distribution_id
  }
}

output "cloudfront_domain_names" {
  description = "Map of domain names to CloudFront distribution domain names"
  value = {
    for domain, site in module.site : domain => site.cloudfront_domain_name
  }
}

output "site_urls" {
  description = "Map of domain names to HTTPS URLs"
  value = {
    for domain in keys(module.site) : domain => "https://${domain}"
  }
}
```

## Cross-Layer Data Sources

This layer discovers resources from the `domains` layer using AWS data sources.

### Route53 Hosted Zone Lookup

```hcl
# Discover hosted zones created by domains layer
data "aws_route53_zone" "site" {
  for_each = var.sites

  name         = each.key
  private_zone = false
}
```

### ACM Certificate Lookup

```hcl
# Discover certificates created by domains layer
data "aws_acm_certificate" "site" {
  provider = aws.us_east_1  # Certificates must be in us-east-1 for CloudFront

  for_each = var.sites

  domain      = each.key
  statuses    = ["ISSUED"]
  most_recent = true
}
```

**Usage in module or resources**:
- `zone_id = data.aws_route53_zone.site[each.key].zone_id`
- `certificate_arn = data.aws_acm_certificate.site[each.key].arn`

## Terraform Configuration

### Backend Configuration (Initially Commented)

```hcl
# backend.tf
# Uncomment after tfstate-backend layer is deployed

# terraform {
#   backend "s3" {
#     bucket         = "noise2signal-terraform-state"
#     key            = "noise2signal/sites.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "noise2signal-terraform-state-lock"
#     encrypt        = true
#   }
# }
```

### Provider Configuration

Dual-region: default + us-east-1 for ACM certificate lookups and CloudFront (global service).

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

  # Assume sites-terraform-role from RBAC layer
  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/sites-terraform-role"
    session_name = "terraform-sites-session"
  }

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "sites-layer"
      Layer       = "4-sites"
    }
  }
}

# ACM certificate data source requires us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/sites-terraform-role"
    session_name = "terraform-sites-us-east-1-session"
  }

  default_tags {
    tags = {
      Owner       = "Noise2Signal LLC"
      Terraform   = "true"
      ManagedBy   = "sites-layer"
      Layer       = "4-sites"
    }
  }
}
```

### Variables

```hcl
# variables.tf
variable "aws_region" {
  description = "Primary AWS region for S3 buckets"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID (for IAM role ARN construction)"
  type        = string
}

variable "sites" {
  description = "Map of static sites to manage"
  type = map(object({
    project_name = string
    price_class  = string
    error_page_path = string
  }))

  validation {
    condition = alltrue([
      for domain in keys(var.sites) : can(regex("^[a-z0-9-]+\\.[a-z]{2,}$", domain))
    ])
    error_message = "Site domain names must be valid DNS names (lowercase, no www prefix)."
  }
}

variable "default_cloudfront_price_class" {
  description = "Default CloudFront price class (can be overridden per site)"
  type        = string
  default     = "PriceClass_100"  # US, Canada, Europe

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.default_cloudfront_price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}
```

### Example terraform.tfvars

```hcl
# terraform.tfvars
aws_account_id = "123456789012"  # Replace with actual account ID

sites = {
  "camdenwander.com" = {
    project_name    = "Camden Wander Personal Site"
    price_class     = "PriceClass_100"
    error_page_path = "/404.html"
  }
  # Add additional sites as needed:
  # "example.com" = {
  #   project_name    = "Example Site"
  #   price_class     = "PriceClass_100"
  #   error_page_path = "/404.html"
  # }
}

default_cloudfront_price_class = "PriceClass_100"
```

## Deployment Process

### Prerequisites
- RBAC layer deployed (Layer 1) - `sites-terraform-role` exists
- Domains layer deployed (Layer 3) - Hosted zones and certificates exist
- Optionally, tfstate-backend layer deployed (Layer 2)
- Domain DNS propagated and certificate validated
- AWS CLI configured
- Terraform 1.5+ installed

### Initial Deployment

1. **Navigate to sites layer**
   ```bash
   cd /workspace/sites
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
   # Review: S3 buckets, CloudFront distributions, Route53 records
   ```

5. **Apply sites configuration**
   ```bash
   terraform apply tfplan
   ```

6. **Wait for CloudFront deployment** (15-30 minutes)
   ```bash
   aws cloudfront wait distribution-deployed \
     --id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camdenwander.com"]')
   ```

7. **Upload website content**
   ```bash
   aws s3 sync ./website-content/ s3://camdenwander.com/ --delete
   ```

8. **Test site accessibility**
   ```bash
   curl -I https://camdenwander.com
   curl -I https://www.camdenwander.com
   # Both should return 200 OK
   ```

9. **Optional: Migrate to remote state** (after tfstate-backend layer deployed)
   ```bash
   # Uncomment backend.tf
   terraform init -migrate-state
   ```

### Adding New Sites

1. Ensure domain exists in `domains` layer (zone + certificate validated)
2. Add site to `sites` variable in `terraform.tfvars`
3. Run `terraform plan` - preview new infrastructure
4. Apply changes
5. Wait for CloudFront deployment (~15-30 minutes)
6. Upload website content to new S3 bucket
7. Test site accessibility (apex + www)

## Content Deployment

### Manual Upload

```bash
# Sync local files to S3
aws s3 sync ./build/ s3://camdenwander.com/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camdenwander.com"]') \
  --paths "/*"
```

### CI/CD Integration (GitHub Actions Example)

```yaml
# .github/workflows/deploy-camdenwander.yml
name: Deploy camdenwander.com

on:
  push:
    branches: [main]
    paths:
      - 'websites/camdenwander/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/sites-terraform-role
          aws-region: us-east-1

      - name: Sync to S3
        run: |
          aws s3 sync ./websites/camdenwander/build/ s3://camdenwander.com/ --delete

      - name: Invalidate CloudFront Cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ secrets.CAMDENWANDER_DISTRIBUTION_ID }} \
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
- DNSSEC (optional, configured in `domains` layer)
- Alias records (not CNAME for apex, avoids DNS resolution issues)

### Content Security
- No sensitive data in S3 buckets (public website content only)
- 404 page does not leak directory structure
- Error responses do not expose backend details

## Dependencies

### Upstream Dependencies
- `scp` layer (Layer 0) - Allows S3, CloudFront, Route53 services
- `rbac` layer (Layer 1) - Provides `sites-terraform-role`
- `tfstate-backend` layer (Layer 2) - Optional, provides remote state backend
- `domains` layer (Layer 3) - Provides hosted zones and ACM certificates (via data sources)

### Downstream Dependencies
- None (this is the top application layer)

## Cost Estimates

**Per site monthly costs**:
- S3 storage: ~$0.023/GB (minimal for static sites, typically <100MB)
- S3 requests: ~$0.005 per 1K requests
- CloudFront data transfer: ~$0.085/GB (PriceClass_100, first 10TB)
- CloudFront requests: ~$0.0075 per 10K HTTPS requests
- Route53 queries: Included in domain layer zone cost

**Estimated total per site**: $1-5/month (varies by traffic)

**For low-traffic site (~10GB/month, 100K requests)**: ~$1.50/month

**Scaling**: Each additional site adds similar costs based on individual traffic

## Testing & Validation

### Post-Deployment Checks
- [ ] S3 buckets created (primary + www redirect)
- [ ] CloudFront distribution deployed (status: Deployed)
- [ ] Route53 A/AAAA records pointing to CloudFront
- [ ] HTTPS works for apex domain
- [ ] HTTPS works for www subdomain
- [ ] HTTP redirects to HTTPS
- [ ] WWW redirects to apex (or vice versa based on config)
- [ ] 404 error page displays correctly
- [ ] Security headers present

### Validation Commands

```bash
# Check S3 buckets
aws s3 ls s3://camdenwander.com/
aws s3 ls s3://www.camdenwander.com/

# Check CloudFront distribution status
aws cloudfront get-distribution \
  --id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camdenwander.com"]') \
  | jq -r '.Distribution.Status'
# Should output: Deployed

# Test DNS resolution
dig camdenwander.com A +short
dig www.camdenwander.com A +short

# Test HTTPS
curl -I https://camdenwander.com
curl -I https://www.camdenwander.com

# Test HTTP redirect
curl -I http://camdenwander.com
# Should show: 301 Moved Permanently, Location: https://...

# Test security headers
curl -I https://camdenwander.com | grep -i "strict-transport-security"

# Test 404 page
curl -I https://camdenwander.com/nonexistent-page
# Should show: 404 Not Found
```

## Maintenance & Updates

### CloudFront Cache Invalidation

After updating website content:

```bash
# Invalidate all paths
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camdenwander.com"]') \
  --paths "/*"

# Or specific paths
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/index.html" "/css/*"
```

**Cost Note**: First 1,000 invalidation paths per month are free, then $0.005 per path.

### S3 Bucket Version Cleanup

If versioning accumulates old files:

```bash
# List versions
aws s3api list-object-versions --bucket camdenwander.com

# Lifecycle policy will automatically clean up versions >90 days old
# Manual cleanup if needed (use with caution)
```

### CloudFront Distribution Updates

Changing CloudFront configuration (cache policies, origins, security headers) triggers redeployment (15-30 minutes).

### Adding/Removing Sites

**Adding**:
1. Ensure domain exists in `domains` layer (zone + certificate validated)
2. Add to `sites` variable in `terraform.tfvars`
3. Apply Terraform changes
4. Wait for CloudFront deployment
5. Upload content
6. Test accessibility

**Removing**:
1. Back up S3 content if needed
2. Remove from `sites` variable
3. Apply Terraform changes (destroys S3, CloudFront, DNS records)
4. Optionally clean up bucket versions manually

## Troubleshooting

### CloudFront Returns 403 Forbidden

**Causes**:
- S3 bucket policy not configured correctly
- OAC not attached to distribution
- File doesn't exist in S3
- Bucket is empty

**Resolution**:
```bash
# Verify bucket policy
aws s3api get-bucket-policy --bucket camdenwander.com

# Check OAC configuration
terraform state show 'aws_cloudfront_origin_access_control.site["camdenwander.com"]'

# Verify files exist
aws s3 ls s3://camdenwander.com/
aws s3 ls s3://camdenwander.com/index.html
```

### DNS Not Resolving

**Causes**:
- Route53 records not created
- DNS propagation delay (up to 48 hours, usually minutes)
- Data source lookup failed (zone or certificate not found)

**Resolution**:
```bash
# Check Route53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -json -state=../domains/terraform.tfstate hosted_zone_ids | jq -r '.["camdenwander.com"]') \
  | jq '.ResourceRecordSets[] | select(.Name | contains("camdenwander.com"))'

# Test DNS resolution
dig camdenwander.com @8.8.8.8
dig www.camdenwander.com @8.8.8.8
```

### Certificate Errors

**Causes**:
- ACM certificate not found (check `domains` layer)
- Certificate in wrong region (must be us-east-1)
- Certificate not yet validated (status: PENDING_VALIDATION)
- Domain name mismatch

**Resolution**:
```bash
# Verify certificate exists and is ISSUED
aws acm list-certificates --region us-east-1 \
  | jq '.CertificateSummaryList[] | select(.DomainName == "camdenwander.com")'

# Check data source discovery
terraform console
> data.aws_acm_certificate.site["camdenwander.com"].arn
> data.aws_acm_certificate.site["camdenwander.com"].status
```

### CloudFront Deployment Stuck

**Causes**:
- AWS internal issue (rare)
- Invalid configuration (certificate, origin, OAC)

**Resolution**:
```bash
# Check distribution status and details
aws cloudfront get-distribution \
  --id $(terraform output -json cloudfront_distribution_ids | jq -r '.["camdenwander.com"]') \
  | jq '.Distribution.Status, .Distribution.DistributionConfig.Origins'

# If truly stuck (>60 minutes), may need to destroy and recreate
terraform destroy -target='module.site["camdenwander.com"]'
terraform apply
```

### Module Not Found Error

**Symptoms**: "Module not found" or "Module path does not exist"

**Causes**:
- Incorrect module source path
- Module directory doesn't exist
- Using module but it's not yet created

**Resolution**:
```bash
# Verify module exists (if using module pattern)
ls -la /workspace/modules/static-site/

# Check module source in main.tf
grep "source" main.tf
# Should be: source = "../modules/static-site"

# Re-initialize
terraform init
```

## Future Enhancements

- Lambda@Edge for advanced redirects or A/B testing
- CloudFront Functions for lightweight transformations (URL rewrites)
- WAF integration for DDoS protection (if needed)
- CloudWatch alarms for 4xx/5xx error rates
- S3 lifecycle policies for content cleanup
- Multi-region S3 replication (disaster recovery)
- CloudFront access logging (to separate S3 bucket for analytics)

## References

- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [CloudFront Custom Error Pages](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/GeneratingCustomErrorResponses.html)
- [Security Headers Best Practices](https://owasp.org/www-project-secure-headers/)
- [CloudFront Performance Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/best-practices.html)
