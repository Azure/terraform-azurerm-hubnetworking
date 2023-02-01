# Create rgs as defined by var.hub_networks
resource "azurerm_resource_group" "rg" {
  for_each = { for rg in local.resource_group_data : rg.name => rg }
  name     = each.key
  location = each.value.location
  tags     = each.value.tags
}

# Module to create virtual networks and subnets
# Useful outputs:
# - vnet_id - the resource id of vnet
# - vnet_subnets_name_ids - a map of subnet name to subnet resource id, e.g. use lookup(module.hub_virtual_networks["key"].vnet_subnets_name_id, "subnet1")
module "hub_virtual_networks" {
  for_each = var.hub_virtual_networks
  source   = "https://github.com/Azure/terraform-azurerm-subnets"
  version  = "1.0.0"
  # ... TODO add required inputs

  # added to make sure dependency graph is correct
  resource_group_name = each.value.resource_group_creation_enabled ? azurerm_resource_group.rg[each.value.resource_group_name].name : each.value.resource_group_name
}


resource "azurerm_virtual_network_peering" "hub_peering" {
  for_each = local.hub_peering_map
  name     = each.key
  # added to make sure dependency graph is correct
  resource_group_name       = azurerm_resource_group.rg[var.hub_virtual_networks[each.key].resource_group_name].name
  virtual_network_name      = var.hub_virtual_networks[each.key].name
  remote_virtual_network_id = each.value.remote_virtual_network_id

  allow_forwarded_traffic      = each.value.allow_forwarded_traffic
  allow_gateway_transit        = each.value.allow_gateway_transit
  use_remote_gateways          = each.value.use_remote_gateways
  allow_virtual_network_access = each.value.allow_virtual_network_access
}

resource "azurerm_route_table" "hub_routing" {
  for_each = local.route_map
  name     = "${each.key}-rt"
  location = var.hub_virtual_networks[each.key].location
  resource_group_name = azurerm_resource_group.rg[var.hub_virtual_networks[each.key].resource_group_name].name
  disable_bgp_route_propagation = false

  dynamic "routes" {
    for_each = toset(each.value)
    content {
      name                   = routes.value.name
      address_prefix         = routes.value.address_prefix
      next_hop_type          = routes.value.next_hop_type
      next_hop_in_ip_address = routes.value.next_hop_ip_address
    }
  }
}

module "azure_firewall" {
  source = "..."
  # TODO
}
