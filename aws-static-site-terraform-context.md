# AWS Static Site Infrastructure - Terraform Context

## Project Overview

This Terraform configuration will provision a complete static website hosting infrastructure for **Noise2Signal LLC** using AWS services. The site will be served from S3 via CloudFront CDN with automatic SSL certificate management.

## Business Entity Context

- **Legal Entity**: Noise2Signal LLC (single-member LLC)
- **Domain**: camden-wander.com (and www subdomain)
- **Current Registrar**: Network Solutions (personal account)
- **Target Ownership**: Domain and all infrastructure owned by Noise2Signal LLC

## Domain Transfer Requirements

### Pre-Terraform Steps (Manual)
1. Domain will be transferred from Network Solutions to AWS Route 53
2. Transfer process establishes Noise2Signal LLC as the registrant
3. This ensures SSL certificate is issued to "Noise2Signal LLC" from day one
4. Unlock domain at Network Solutions and obtain transfer authorization code before running Terraform

### Post-Transfer (Terraform Manages)
- Route 53 hosted zone for DNS management
- All DNS records (A, AAAA, CNAME for CloudFront)
- Domain auto-renewal and registrar lock settings

## Infrastructure Components

### 1. Route 53 (DNS Management)

**Requirements:**
- Hosted zone for camden-wander.com
- A and AAAA records pointing to CloudFront distribution (apex domain)
- CNAME record for www subdomain pointing to CloudFront
- Support for both apex and www subdomain routing to same CloudFront distribution
- Optional: CAA records specifying only AWS Certificate Manager can issue certificates

**Notes:**
- Domain registration transfer happens outside Terraform initially
- Terraform manages the hosted zone and records post-transfer
- Consider adding health checks for monitoring (optional, adds cost)

### 2. ACM (SSL Certificate Management)

**Requirements:**
- Certificate for camden-wander.com with Subject Alternative Names (SANs) for:
  - camden-wander.com (apex)
  - www.camden-wander.com (www subdomain)
- Certificate **must be in us-east-1 region** (CloudFront requirement)
- DNS validation method (automatic via Route 53)
- Automatic renewal enabled
- Certificate issued to registrant: Noise2Signal LLC

**Notes:**
- ACM certificates are free when used with AWS services
- DNS validation records should be created automatically in Route 53
- Wait for certificate validation before creating CloudFront distribution

### 3. S3 (Static Content Storage)

**Requirements:**

**Primary Bucket (camden-wander.com):**
- Bucket name: camden-wander.com (must match domain for S3 static hosting)
- Public read access via bucket policy (CloudFront origin access)
- Static website hosting enabled
- Index document: index.html
- Error document: 404.html
- Versioning: Optional, recommended for rollback capability
- Server-side encryption: AES256 (default)

**Redirect Bucket (www.camden-wander.com):**
- Bucket name: www.camden-wander.com
- Website redirect to apex domain (https://camden-wander.com)
- Minimal configuration, exists only for redirect

**Security:**
- Block public ACLs (use bucket policy instead)
- CloudFront Origin Access Identity (OAI) or Origin Access Control (OAC) for secure access
- Bucket policy grants read access only to CloudFront
- No public write access under any circumstances

**Tags:**
- Owner: Noise2Signal LLC
- Environment: Production
- Terraform: true

### 4. CloudFront (CDN)

**Requirements:**

**Primary Distribution:**
- Origin: S3 bucket (camden-wander.com)
- Origin Access Control (OAC) - modern replacement for OAI
- Alternate domain names (CNAMEs): camden-wander.com, www.camden-wander.com
- SSL certificate: ACM certificate from us-east-1
- SSL/TLS security policy: TLSv1.2_2021 (or latest recommended)
- Default root object: index.html
- Price class: PriceClass_100 (US, Canada, Europe) or PriceClass_All based on audience
- IPv6 enabled: true

**Cache Behavior:**
- Viewer protocol policy: Redirect HTTP to HTTPS
- Allowed methods: GET, HEAD (static site, no POST/PUT/DELETE)
- Cached methods: GET, HEAD
- Compress objects: true (automatic gzip/brotli)
- Cache policy: CachingOptimized (or custom based on needs)
- Origin request policy: CORS-S3Origin (if needed)

**Error Pages:**
- 403 Forbidden → /404.html (response code: 404)
- 404 Not Found → /404.html (response code: 404)
- Optional: Custom error page for 500s

**Security Headers (Optional but Recommended):**
- Response headers policy for:
  - Strict-Transport-Security: max-age=63072000
  - X-Content-Type-Options: nosniff
  - X-Frame-Options: DENY
  - X-XSS-Protection: 1; mode=block
  - Referrer-Policy: strict-origin-when-cross-origin

**Logging (Optional):**
- Access logs to separate S3 bucket
- Consider cost vs. benefit for personal site

**Tags:**
- Owner: Noise2Signal LLC
- Environment: Production
- Terraform: true

## Terraform Configuration Considerations

### State Management
- Remote state in S3 bucket (separate from website content)
- State locking via DynamoDB table
- State encryption enabled

### Variables to Parameterize
- `domain_name` - apex domain (camden-wander.com)
- `www_domain_name` - www subdomain
- `environment` - "production"
- `owner` - "Noise2Signal LLC"
- `aws_region` - "us-east-1" (for ACM/CloudFront)
- `s3_bucket_region` - Can be different from us-east-1 if desired
- `price_class` - CloudFront price class

### Outputs Needed
- CloudFront distribution domain name (for DNS records)
- CloudFront distribution ID (for cache invalidation)
- S3 bucket name(s)
- ACM certificate ARN
- Route 53 hosted zone ID
- Route 53 name servers (for verification if transferring domain)

### Module Structure Consideration
- Consider breaking into modules: `dns`, `storage`, `cdn`, `ssl`
- Or single root module for simplicity (personal site scale)
- Whichever approach is preferred, ensure clean separation of concerns

## Dependencies and Ordering

1. **First**: Route 53 hosted zone (after domain transfer)
2. **Second**: ACM certificate with DNS validation records in Route 53
3. **Third**: Wait for certificate validation (use `aws_acm_certificate_validation`)
4. **Fourth**: S3 buckets with proper policies
5. **Fifth**: CloudFront distribution with validated certificate
6. **Sixth**: Route 53 A/AAAA records pointing to CloudFront

Terraform should handle these dependencies automatically via resource references.

## Security Checklist Items

- [ ] S3 buckets not publicly listable (block public ACLs)
- [ ] CloudFront uses OAC, not public bucket access
- [ ] Certificate covers both apex and www
- [ ] HTTPS enforced (HTTP redirects to HTTPS)
- [ ] Security headers configured in CloudFront
- [ ] No hardcoded credentials in Terraform code
- [ ] State file is encrypted and not in version control
- [ ] IAM policies follow least privilege
- [ ] CloudFormation stack drift detection (if used)
- [ ] Tags applied consistently for cost tracking

## Post-Deployment Steps

1. Upload website content to S3 bucket (sync local files)
2. Test both apex (camden-wander.com) and www subdomain
3. Verify HTTP redirects to HTTPS
4. Test 404 error page
5. Check security headers (securityheaders.com)
6. Monitor CloudFront metrics in CloudWatch
7. Set up billing alerts for unexpected costs
8. Document cache invalidation procedure for future updates

## Future Enhancements (Not in Initial Config)

- CloudWatch alarms for 4xx/5xx error rates
- Lambda@Edge for advanced routing/redirects
- WAF for DDoS protection (overkill for personal site, but consider if needed)
- S3 bucket replication for disaster recovery
- CloudFront Functions for lightweight transformations
- Separate staging environment (staging.camden-wander.com)

## Cost Estimates (Monthly)

- Route 53 hosted zone: $0.50
- Route 53 queries: ~$0.40 (1M queries)
- S3 storage: ~$0.023/GB (minimal for static site)
- S3 requests: ~$0.005 per 1K requests
- CloudFront: Free tier first 12 months (50GB, 2M requests)
- CloudFront post-free-tier: ~$0.085/GB (US/Canada)
- ACM certificates: Free
- **Estimated Total: $1-7/month** depending on traffic

## Notes for Claude Code Generation

- Use latest Terraform AWS provider version (5.x)
- Include appropriate `required_providers` block
- Use `terraform fmt` standards for formatting
- Include comments for complex configurations
- Use `locals` block for derived values
- Prefer explicit dependencies over implicit where ambiguous
- Include validation rules for variables where appropriate
- Use consistent naming conventions (kebab-case for resources)
- Generate a README.md with usage instructions
- Include example `terraform.tfvars.example` file
