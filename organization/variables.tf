variable "proprietary_signals_email" {
  type        = string
  description = "Email address for Proprietary Signals account root user (must be globally unique)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.proprietary_signals_email))
    error_message = "Must be a valid email address."
  }
}

variable "aws_service_access_principals" {
  type        = list(string)
  description = "AWS services that can be integrated with the organization"
  default = [
    "sso.amazonaws.com",  # IAM Identity Center
  ]
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
  }
}
