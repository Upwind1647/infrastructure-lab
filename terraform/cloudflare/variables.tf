variable "cloudflare_account_id" {
  description = "Cloudflare account identifier"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone identifier for northlift.net"
  type        = string
}

variable "github_idp_id" {
  description = "Cloudflare Access GitHub identity provider ID"
  type        = string
}

variable "tunnel_secret" {
  description = "Base64-encoded existing tunnel secret used by cloudflared connectors"
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(regex("^[A-Za-z0-9+/]+={0,2}$", var.tunnel_secret)) &&
      length(var.tunnel_secret) % 4 == 0
    )
    error_message = "tunnel_secret must be a syntactically valid base64 value."
  }

  validation {
    condition     = length(var.tunnel_secret) >= 44
    error_message = "tunnel_secret must represent at least 32 bytes (minimum base64 length 44)."
  }
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  type        = string
  default     = "lab-internal-services"
}

variable "access_allowed_emails" {
  description = "Named user emails allowed to access protected hostnames"
  type        = list(string)
}

variable "access_session_duration" {
  description = "Session duration for Access applications and policies"
  type        = string
  default     = "24h"
}

variable "access_scope" {
  description = "Scope for Access resources: zone or account"
  type        = string
  default     = "zone"

  validation {
    condition     = contains(["zone", "account"], var.access_scope)
    error_message = "access_scope must be either 'zone' or 'account'."
  }
}

variable "tunnel_network_routes" {
  description = "Optional private network routes for the tunnel (CIDR based)"
  type = map(object({
    network            = string
    comment            = optional(string)
    virtual_network_id = optional(string)
  }))
  default = {}
}
// trigger ci for email update
