output "k3s_vm_ip" {
  description = "The assigned IP address of the K3s VM"
  value       = proxmox_virtual_environment_vm.k3s_node.ipv4_addresses[1][0]
}

output "ssh_command" {
  description = "SSH command to connect to the new K3s node"
  value       = "ssh adminsetup@${proxmox_virtual_environment_vm.k3s_node.ipv4_addresses[1][0]}"
}
