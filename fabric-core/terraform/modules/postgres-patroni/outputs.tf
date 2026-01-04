output "patroni_inventory" {
  description = "Inventory data for Patroni nodes."
  value = {
    for name, node in proxmox_lxc.patroni : name => {
      hostname = node.hostname
      node     = node.target_node
      vmid     = node.vmid
    }
  }
}

output "haproxy_inventory" {
  description = "Inventory data for HAProxy nodes."
  value = {
    for name, node in proxmox_lxc.haproxy : name => {
      hostname = node.hostname
      node     = node.target_node
      vmid     = node.vmid
    }
  }
}
