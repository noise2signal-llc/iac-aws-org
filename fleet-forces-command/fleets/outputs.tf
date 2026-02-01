output "domestic_fleet_ids" {
  value = [aws_organizations_account.domestic_noise.id, aws_organizations_account.domestic_signals.id]
}
