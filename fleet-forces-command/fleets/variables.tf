variable "domestic_fleet_ou_id" {
  type = string
}

variable "domestic_signal_fleet_email" {
  type = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.domestic_signal_fleet_email))
    error_message = "Must be a valid email address."
  }
}

variable "domestic_noise_fleet_email" {
  type = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.domestic_noise_fleet_email))
    error_message = "Must be a valid email address."
  }
}
