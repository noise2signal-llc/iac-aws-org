variable "common_tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    Organization = "Noise2Signal LLC"
    ManagedBy    = "terraform"
  }
}
