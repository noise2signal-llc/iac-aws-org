variable "member_email" {
  type        = string
  description = "Email address for Proprietary Signals account root user (must be globally unique)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.member_email))
    error_message = "Must be a valid email address."
  }
}

variable "proprietary_signals_email" {
  type        = string
  description = "Email address for Proprietary Signals account root user (must be globally unique)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.proprietary_signals_email))
    error_message = "Must be a valid email address."
  }
}

