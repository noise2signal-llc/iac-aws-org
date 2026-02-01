variable "sso_admiral_email" {
  type        = string
  description = "Email address for Proprietary Signals account root user (must be globally unique)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sso_admiral_email))
    error_message = "Must be a valid email address."
  }
}

variable "rear_admiral_email" {
  type        = string
  description = "Email address for Proprietary Signals account root user (must be globally unique)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.rear_admiral_email))
    error_message = "Must be a valid email address."
  }
}

# List of AWS accounts the Rear Admiral has Administrative access to
variable "rear_admiral_commands" {
  type = map(any)
}
