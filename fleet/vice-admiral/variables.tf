variable "management_account_email" {
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.management_account_email))
    error_message = "Must be a valid email address."
  }
}

variable "proprietary_signals_account_email" {
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.proprietary_signals_account_email))
    error_message = "Must be a valid email address."
  }
}

variable "sso_admiral_email" {
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sso_admiral_email))
    error_message = "Must be a valid email address."
  }
}
