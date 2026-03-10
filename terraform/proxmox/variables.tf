variable "proxmox_host" {
  type        = string
  description = "192.168.x.x:8006 or DNS"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "ID Proxmox API Token"
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API Tokens"
  sensitive   = true
}

variable "proxmox_node_name" {
  type        = string
  description = "The name of the Proxmox node"
}

# ssh_public_key not necessary because of setup_me.sh
