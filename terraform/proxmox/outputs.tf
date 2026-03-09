output "k3s_vm_ip" {
  description = "The assigned IP address of the K3s VM"
  # We retrieve the first IP [0] of the first network interface [1]
  value       = proxmox_virtual_environment_vm.k3s_node.ipv4_addresses[1][0]
}

output "ssh_command" {
  description = "SSH command to connect to the new K3s node"
  # Same correction here for the string
  value       = "ssh adminsetup@${proxmox_virtual_environment_vm.k3s_node.ipv4_addresses[1][0]}"
}
