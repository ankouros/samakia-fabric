output "vmid" {
  description = "Proxmox VMID of the LXC container."
  value       = proxmox_lxc.this.vmid
}

output "hostname" {
  description = "Hostname of the LXC container."
  value       = proxmox_lxc.this.hostname
}

output "node" {
  description = "Proxmox node where the container is running."
  value       = proxmox_lxc.this.target_node
}
