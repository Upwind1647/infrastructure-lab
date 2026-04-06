locals {
  # Add new protected services here to enforce Zero Trust Access policies.
  protected_apps = {
    argocd = {
      domain            = "argocd.northlift.net"
      policy_precedence = 1
    }
  }

  access_scope_is_account = var.access_scope == "account"
}

resource "cloudflare_zero_trust_access_application" "protected" {
  for_each = local.protected_apps

  account_id = local.access_scope_is_account ? var.cloudflare_account_id : null
  zone_id    = local.access_scope_is_account ? null : var.cloudflare_zone_id
  name       = "${each.key}-access"
  domain     = each.value.domain

  type                      = "self_hosted"
  session_duration          = var.access_session_duration
  app_launcher_visible      = false
  auto_redirect_to_identity = false
  allowed_idps              = [var.github_idp_id]
}

resource "cloudflare_zero_trust_access_policy" "allowed_emails" {
  for_each = local.protected_apps

  account_id     = local.access_scope_is_account ? var.cloudflare_account_id : null
  zone_id        = local.access_scope_is_account ? null : var.cloudflare_zone_id
  application_id = cloudflare_zero_trust_access_application.protected[each.key].id
  name           = "${each.key}-allow"
  decision       = "allow"
  precedence     = each.value.policy_precedence

  session_duration = var.access_session_duration

  include {
    email = var.access_allowed_emails
  }

  require {
    login_method = [var.github_idp_id]
  }
}
