# Create rgs as defined by var.hub_networks
resource "azurerm_resource_group" "rg" {
  for_each = { for rg in local.resource_group_data : rg.name => rg }

  location = each.value.location
  name     = each.key
  tags     = each.value.tags
}

# Module to create virtual networks and subnets
# Useful outputs:
# - vnet_id - the resource id of vnet
# - vnet_subnets_name_ids - a map of subnet name to subnet resource id, e.g. use lookup(module.hub_virtual_networks["key"].vnet_subnets_name_id, "subnet1")
module "hub_virtual_networks" {
  for_each = var.hub_virtual_networks
  source   = "Azure/subnets/azurerm"
  version  = "1.0.0"
  # ... TODO add required inputs

  # added to make sure dependency graph is correct
  virtual_network_name          = each.value.name
  virtual_network_address_space = each.value.address_space
  virtual_network_location      = each.value.location
  resource_group_name           = try(azurerm_resource_group.rg[each.value.resource_group_name].name, each.value.resource_group_name)
  virtual_network_bgp_community = each.value.bgp_community
  virtual_network_ddos_protection_plan = each.value.ddos_protection_plan_id == null ? null : {
    id     = each.value.ddos_protection_plan_id
    enable = true
  }
  virtual_network_dns_servers             = each.value.dns_servers
  virtual_network_flow_timeout_in_minutes = each.value.flow_timeout_in_minutes
  virtual_network_tags                    = each.value.tags
  subnets                                 = try(local.subnets_map[each.key], {})
}

locals {
  virtual_networks_modules = { for vnet_name, vnet_module in module.hub_virtual_networks : vnet_name => vnet_module }
}

resource "azurerm_virtual_network_peering" "hub_peering" {
  for_each = local.hub_peering_map

  name = each.key
  # added to make sure dependency graph is correct
  remote_virtual_network_id    = each.value.remote_virtual_network_id
  resource_group_name          = try(azurerm_resource_group.rg[var.hub_virtual_networks[each.key].resource_group_name].name, var.hub_virtual_networks[each.key].resource_group_name)
  virtual_network_name         = each.value.virtual_network_name
  allow_forwarded_traffic      = each.value.allow_forwarded_traffic
  allow_gateway_transit        = each.value.allow_gateway_transit
  allow_virtual_network_access = each.value.allow_virtual_network_access
  use_remote_gateways          = each.value.use_remote_gateways
}

resource "azurerm_route_table" "hub_routing" {
  for_each = local.route_map

  location                      = var.hub_virtual_networks[each.key].location
  name                          = "${each.key}-rt"
  resource_group_name           = azurerm_resource_group.rg[var.hub_virtual_networks[each.key].resource_group_name].name
  disable_bgp_route_propagation = false
  tags                          = {}

  dynamic "route" {
    for_each = toset(each.value)

    content {
      address_prefix         = route.value.address_prefix
      name                   = route.value.name
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = route.value.next_hop_ip_address
    }
  }
}

locals {
  hub_routing = azurerm_route_table.hub_routing
}

resource "azurerm_subnet_route_table_association" "hub_routing_creat" {
  for_each = local.subnet_route_table_association_map

  route_table_id = each.value.route_table_id
  subnet_id      = each.value.subnet_id
}

resource "azurerm_subnet_route_table_association" "hub_routing_external" {
  for_each = local.subnet_external_route_table_association_map

  route_table_id = each.value.route_table_id
  subnet_id      = each.value.subnet_id
}

#module "azure_firewall" {
#  source = "..."
#  # TODO
#}
