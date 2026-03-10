terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.98.1"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}/api2/json"
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file("~/.ssh/id_ed25519")
  }
}
