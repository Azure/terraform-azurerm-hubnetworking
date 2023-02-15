locals {
  virtual_networks_modules = {
    for vnet in var.hub_virtual_networks :
    vnet.name => {
      vnet_name = vnet.name
      vnet_id = "${vnet.name}_id"
      vnet_subnets_name_id = {for subnet_name, subnet in vnet.subnets : subnet_name => "${subnet_name}_id"}
    }
  }
}