output "tunnel_id" {
  description = "Cloudflare Tunnel UUID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.lab_internal.id
}

output "tunnel_cname_target" {
  description = "CNAME target used by tunnel DNS hostnames"
  value       = cloudflare_zero_trust_tunnel_cloudflared.lab_internal.cname
}

output "access_application_ids" {
  description = "Access application IDs by service key"
  value       = { for key, app in cloudflare_zero_trust_access_application.protected : key => app.id }
}

output "access_policy_ids" {
  description = "Access policy IDs by service key"
  value       = { for key, policy in cloudflare_zero_trust_access_policy.allowed_emails : key => policy.id }
}
