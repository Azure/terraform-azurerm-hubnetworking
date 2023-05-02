locals {
  hub_routing = {
    for vnet in var.hub_virtual_networks :
    vnet.name => {
      id = "${vnet.name}_route_table_id"
    }
  }
  firewall_private_ip = {
    for vnet_name, vnet in var.hub_virtual_networks : vnet_name => "${vnet_name}-fake-fw-private-ip"
    if vnet.firewall != null
  }
  virtual_networks_modules = {
    for k, vnet in var.hub_virtual_networks :
    k => {
      vnet_name            = vnet.name
      vnet_id              = "${vnet.name}_id"
      vnet_location        = vnet.location
      vnet_subnets_name_id = { for subnet_name, subnet in vnet.subnets : subnet_name => "${subnet_name}_id" }
    }
  }
}
