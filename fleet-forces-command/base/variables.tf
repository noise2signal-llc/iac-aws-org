variable "base_email" {
  type = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.base_email))
    error_message = "Must be a valid email address."
  }
}

variable "base_ou_id" {
  type = string
}

