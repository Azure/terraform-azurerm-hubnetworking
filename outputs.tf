output "firewalls" {
  value = {
    for vnet_name, fw in azurerm_firewall.fw : vnet_name => {
      id                           = fw.id
      name                         = fw.name
      private_ip_address           = try(fw.ip_configuration[0].private_ip_address, null)
      public_ip_address            = try(azurerm_public_ip.fw_default_ip_configuration_pip[vnet_name].ip_address)
      management_public_ip_address = try(azurerm_public_ip.fw_management_ip_configuration_pip[vnet_name].ip_address, null)
    }
  }
  description = "A curated output of the firewalls created by this module."
}

output "hub_route_tables" {
  value = {
    for vnet_name, rt in azurerm_route_table.hub_routing : vnet_name => {
      name = rt.name
      id   = rt.id
      routes = [
        for r in rt.route : {
          name                   = r.name
          address_prefix         = r.address_prefix
          next_hop_type          = r.next_hop_type
          next_hop_in_ip_address = r.next_hop_in_ip_address
        }
      ]
    }
  }
  description = "A curated output of the route tables created by this module."
}

output "resource_groups" {
  value = {
    for rg_name, rg in azurerm_resource_group.rg : rg_name => {
      name     = rg.name
      location = rg.location
      id       = rg.id
    }
  }
  description = "A curated output of the resource groups created by this module."
}

output "virtual_networks" {
  value = {
    for vnet_name, vnet_mod in module.hub_virtual_networks : vnet_name => {
      name                  = vnet_mod.vnet_name
      resource_group_name   = var.hub_virtual_networks[vnet_name].resource_group_name
      id                    = vnet_mod.vnet_id
      location              = vnet_mod.vnet_location
      address_spaces        = vnet_mod.vnet_address_space
      subnets_name_id       = vnet_mod.vnet_subnets_name_id
      hub_router_ip_address = try(azurerm_firewall.fw[vnet_name].ip_configuration[0].private_ip_address, var.hub_virtual_networks[vnet_name].hub_router_ip_address)
    }
  }
  description = "A curated output of the virtual networks created by this module."
}
