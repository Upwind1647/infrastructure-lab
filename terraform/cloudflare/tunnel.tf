locals {
  # Add new hostnames here to automate tunnel DNS routing.
  tunnel_dns_hostnames = {
    argocd = {
      hostname = "argocd.northlift.net"
      proxied  = true
    }
    grafana = {
      hostname = "grafana.northlift.net"
      proxied  = true
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "lab_internal" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = var.tunnel_secret
  config_src = "cloudflare"

  lifecycle {
    ignore_changes = [
      # Existing tunnel imports do not retain these create-time fields in state.
      config_src,
      secret,
    ]
  }
}

resource "cloudflare_record" "tunnel_dns" {
  for_each = local.tunnel_dns_hostnames

  zone_id = var.cloudflare_zone_id
  name    = each.value.hostname
  type    = "CNAME"
  content = cloudflare_zero_trust_tunnel_cloudflared.lab_internal.cname

  proxied         = each.value.proxied
  ttl             = 1
  allow_overwrite = true
}

resource "cloudflare_zero_trust_tunnel_route" "tunnel_networks" {
  for_each = var.tunnel_network_routes

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.lab_internal.id
  network    = each.value.network

  comment            = try(each.value.comment, null)
  virtual_network_id = try(each.value.virtual_network_id, null)
}
