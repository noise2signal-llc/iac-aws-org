# Terraform Reusable Modules - Component Libraries

## Overview

This document defines the standards and patterns for **reusable Terraform modules** used across Noise2Signal LLC infrastructure repositories. Each module is maintained in its own dedicated GitHub repository and versioned independently.

**Module Distribution Pattern**: Git-based module sourcing with semantic versioning

## Module Repository Strategy

### Repository Naming Convention
```
terraform-aws-module-{component}
```

Examples:
- `terraform-aws-module-cdn` - CloudFront distribution patterns
- `terraform-aws-module-storage` - S3 bucket patterns for static sites
- `terraform-aws-module-acm` - ACM certificate management patterns
- `terraform-aws-module-route53-records` - Route53 record patterns

### Module Sourcing Pattern

Modules are sourced via Git URLs with version tags:

```hcl
module "cdn" {
  source = "git::https://github.com/noise2signal/terraform-aws-module-cdn.git?ref=v1.2.0"

  domain_name     = "camden-wander.com"
  certificate_arn = data.aws_acm_certificate.site.arn
  # ... other variables
}
```

**Version pinning**:
- Use specific version tags (e.g., `v1.2.0`) in production
- Use branch names (e.g., `ref=main`) only for development/testing
- Follow semantic versioning (MAJOR.MINOR.PATCH)

## Core Module Standards

### Module Structure (Standard Layout)

Every module repository should follow this structure:

```
terraform-aws-module-{component}/
├── README.md                 # Module documentation
├── main.tf                   # Primary resource definitions
├── variables.tf              # Input variables
├── outputs.tf                # Output values
├── versions.tf               # Terraform and provider version constraints
├── examples/                 # Usage examples
│   ├── basic/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── advanced/
│       ├── main.tf
│       └── variables.tf
├── tests/                    # Terratest or other testing (optional)
└── .gitignore
```

### versions.tf Pattern

```hcl
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

**Note**: Modules should use `>=` for provider versions (minimum version), not `~>` (version locking is the responsibility of the calling code).

### variables.tf Standards

```hcl
variable "domain_name" {
  description = "Primary domain name for the resource"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain must be a valid DNS name (lowercase, no www prefix)."
  }
}

variable "tags" {
  description = "Additional tags to merge with default tags"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}
```

**Best practices**:
- Always include `description` for every variable
- Use `validation` blocks for inputs that have constraints
- Provide sensible `default` values where appropriate
- Use `type` constraints (don't rely on implicit typing)

### outputs.tf Standards

```hcl
output "resource_id" {
  description = "The ID of the created resource"
  value       = aws_resource.example.id
}

output "resource_arn" {
  description = "The ARN of the created resource"
  value       = aws_resource.example.arn
}
```

**Best practices**:
- Every output should have a `description`
- Output all identifiers that calling code might need (ID, ARN, domain name, etc.)
- Use `sensitive = true` for outputs containing secrets

### README.md Template

````markdown
# Terraform AWS Module - {Component Name}

## Description

[1-2 sentence description of what this module does]

## Usage

```hcl
module "example" {
  source = "git::https://github.com/noise2signal/terraform-aws-module-{component}.git?ref=v1.0.0"

  domain_name = "example.com"
  # ... other required variables
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| domain_name | Primary domain name | `string` | n/a | yes |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| resource_id | The ID of the created resource |
| resource_arn | The ARN of the created resource |

## Examples

See `examples/` directory for usage examples.

## License

Proprietary - Noise2Signal LLC
````

## Planned Modules

### 1. terraform-aws-module-cdn (CloudFront)

**Purpose**: Reusable CloudFront distribution pattern for static sites

**Key Features**:
- CloudFront distribution with S3 origin
- Origin Access Control (OAC) integration
- Custom error page handling (403 → 404, etc.)
- Security headers response policy
- Configurable cache behaviors
- IPv6 support

**Input Variables**:
```hcl
variable "domain_name" {
  description = "Primary domain name (apex)"
  type        = string
}

variable "alternate_domain_names" {
  description = "Additional domain names (e.g., www subdomain)"
  type        = list(string)
  default     = []
}

variable "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name (origin)"
  type        = string
}

variable "origin_access_control_id" {
  description = "CloudFront OAC ID for S3 access"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN (must be in us-east-1)"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "enable_security_headers" {
  description = "Enable security headers response policy"
  type        = bool
  default     = true
}

variable "error_page_path" {
  description = "Path to custom error page (e.g., /404.html)"
  type        = string
  default     = "/404.html"
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
```

**Outputs**:
```hcl
output "distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront distribution domain name (for DNS records)"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront hosted zone ID (for Route53 alias records)"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}
```

---

### 2. terraform-aws-module-storage (S3 for Static Sites)

**Purpose**: S3 bucket configuration for static website hosting

**Key Features**:
- Primary content bucket with website hosting enabled
- WWW redirect bucket (optional)
- Versioning and encryption
- Public access blocking
- CloudFront OAC bucket policy

**Input Variables**:
```hcl
variable "bucket_name" {
  description = "S3 bucket name (typically matches domain)"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
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

variable "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN (for bucket policy)"
  type        = string
  default     = null  # If null, no bucket policy created
}

variable "enable_redirect" {
  description = "Configure bucket for redirect (e.g., www → apex)"
  type        = bool
  default     = false
}

variable "redirect_target" {
  description = "Redirect target hostname (if enable_redirect = true)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
```

**Outputs**:
```hcl
output "bucket_id" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "S3 bucket regional domain name (for CloudFront origin)"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_website_endpoint" {
  description = "S3 website endpoint (if website hosting enabled)"
  value       = try(aws_s3_bucket_website_configuration.this[0].website_endpoint, null)
}
```

---

### 3. terraform-aws-module-acm (ACM Certificates)

**Purpose**: ACM certificate provisioning with DNS validation

**Key Features**:
- Certificate request with SANs
- DNS validation via Route53
- Certificate validation wait
- Must provision in us-east-1 for CloudFront

**Input Variables**:
```hcl
variable "domain_name" {
  description = "Primary domain name (apex)"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names (e.g., www subdomain)"
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for DNS validation"
  type        = string
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
```

**Outputs**:
```hcl
output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate.this.arn
}

output "certificate_status" {
  description = "ACM certificate validation status"
  value       = aws_acm_certificate.this.status
}

output "validation_record_fqdns" {
  description = "DNS validation record FQDNs"
  value       = [for record in aws_route53_record.validation : record.fqdn]
}
```

**Note**: This module should be called with `provider = aws.us_east_1` alias when used for CloudFront.

---

### 4. terraform-aws-module-route53-records (DNS Records)

**Purpose**: Route53 alias records pointing to CloudFront

**Key Features**:
- A and AAAA record creation
- Alias record configuration
- Support for apex and subdomain records

**Input Variables**:
```hcl
variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the record"
  type        = string
}

variable "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (alias target)"
  type        = string
}

variable "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  type        = string
}

variable "create_ipv6_record" {
  description = "Create AAAA record for IPv6"
  type        = bool
  default     = true
}
```

**Outputs**:
```hcl
output "a_record_fqdn" {
  description = "FQDN of the created A record"
  value       = aws_route53_record.a.fqdn
}

output "aaaa_record_fqdn" {
  description = "FQDN of the created AAAA record (if created)"
  value       = try(aws_route53_record.aaaa[0].fqdn, null)
}
```

---

## Module Development Workflow

### 1. Initial Module Creation

```bash
# Create new module repository
git clone https://github.com/noise2signal/terraform-aws-module-{component}.git
cd terraform-aws-module-{component}

# Create standard structure
mkdir -p examples/{basic,advanced} tests
touch main.tf variables.tf outputs.tf versions.tf README.md .gitignore
```

### 2. Module Development

- Write resources in `main.tf`
- Define inputs in `variables.tf` with validation
- Export outputs in `outputs.tf`
- Document in `README.md`
- Create usage examples in `examples/`

### 3. Testing

**Manual testing:**
```bash
cd examples/basic
terraform init
terraform plan
terraform apply
# Verify resources work as expected
terraform destroy
```

**Automated testing** (optional, using Terratest):
```go
// tests/module_test.go
package test

import (
  "testing"
  "github.com/gruntwork-io/terratest/modules/terraform"
)

func TestModule(t *testing.T) {
  terraformOptions := &terraform.Options{
    TerraformDir: "../examples/basic",
  }

  defer terraform.Destroy(t, terraformOptions)
  terraform.InitAndApply(t, terraformOptions)

  // Add assertions here
}
```

### 4. Versioning and Tagging

**Semantic versioning:**
- **MAJOR** (v2.0.0): Breaking changes (incompatible API changes)
- **MINOR** (v1.1.0): New features (backwards-compatible)
- **PATCH** (v1.0.1): Bug fixes (backwards-compatible)

```bash
# Create version tag
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0

# Update tag if needed (use with caution)
git tag -f v1.0.0
git push origin v1.0.0 --force
```

### 5. Changelog Maintenance

Maintain `CHANGELOG.md` in each module:

```markdown
# Changelog

## [1.1.0] - 2024-03-15

### Added
- Support for custom cache policies

### Changed
- Default price class to PriceClass_100

### Fixed
- Security headers response policy attachment

## [1.0.0] - 2024-03-01

### Added
- Initial release
- CloudFront distribution with OAC
- Security headers support
```

## Module Consumption Best Practices

### In Calling Code (e.g., terraform-static-sites)

```hcl
module "cdn" {
  source = "git::https://github.com/noise2signal/terraform-aws-module-cdn.git?ref=v1.2.0"

  for_each = { for site in var.sites : site.domain => site }

  domain_name                      = each.value.domain
  alternate_domain_names           = ["www.${each.value.domain}"]
  s3_bucket_regional_domain_name   = module.storage[each.key].bucket_regional_domain_name
  origin_access_control_id         = aws_cloudfront_origin_access_control.site[each.key].id
  certificate_arn                  = data.aws_acm_certificate.site[each.key].arn
  price_class                      = var.cloudfront_price_class
  enable_security_headers          = true

  tags = {
    Project = each.value.project_name
  }
}
```

**Best practices:**
- Pin to specific version tags in production
- Use `for_each` for multi-instance deployments
- Pass through common variables (tags, environment)
- Reference other modules' outputs as inputs (module chaining)

## Module Security Standards

### Least Privilege
- Modules should only create IAM policies with minimum required permissions
- Scope resource ARNs where possible (avoid `*` wildcards)

### Encryption
- Enable encryption by default (S3, CloudWatch logs, etc.)
- Use AWS-managed keys unless customer-managed keys required

### Public Access
- Block public access by default (S3 buckets)
- Require explicit opt-in for public resources

### Tagging
- All modules should accept and merge `tags` variable
- Apply default tags for ownership and Terraform management

## Module Testing Strategy

### Levels of Testing

1. **Syntax validation**: `terraform validate`
2. **Plan verification**: `terraform plan` in examples
3. **Integration testing**: Deploy to test AWS account, verify resources
4. **Automated testing**: Terratest or similar (optional for simple modules)

### Example Test Script

```bash
#!/bin/bash
# test-module.sh

set -e

echo "Testing basic example..."
cd examples/basic
terraform init
terraform validate
terraform plan -out=tfplan

echo "Applying configuration..."
terraform apply tfplan

echo "Running validation checks..."
# Add custom validation here (e.g., curl tests, AWS CLI checks)

echo "Cleaning up..."
terraform destroy -auto-approve

echo "Module test passed!"
```

## Troubleshooting

### Module Not Found
**Error**: `Error downloading modules: Error loading modules: module "cdn": not found`

**Causes**:
- Git URL incorrect
- Version tag doesn't exist
- Private repo without authentication

**Resolution**:
```bash
# Verify tag exists
git ls-remote --tags https://github.com/noise2signal/terraform-aws-module-cdn.git

# For private repos, configure Git credentials
git config --global credential.helper store
```

### Version Conflicts
**Error**: `Module version constraints not satisfied`

**Causes**:
- Provider version mismatch between module and calling code

**Resolution**:
- Update module's `versions.tf` to use `>=` instead of `~>`
- Or update calling code's provider version

### State Drift
**Symptoms**: `terraform plan` shows unexpected changes in module resources

**Causes**:
- Manual changes outside Terraform
- Module upgraded with breaking changes

**Resolution**:
```bash
# Refresh state
terraform refresh

# If module changed, update version pin and review changes
terraform plan
```

## Future Enhancements

- Private Terraform registry (eliminates Git URL complexity)
- Automated module testing in CI/CD
- Module usage analytics (which versions are deployed where)
- Shared module library documentation site
- Module composition patterns (modules calling other modules)

## References

- [Terraform Module Development](https://developer.hashicorp.com/terraform/language/modules/develop)
- [Semantic Versioning](https://semver.org/)
- [Terratest](https://terratest.gruntwork.io/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
