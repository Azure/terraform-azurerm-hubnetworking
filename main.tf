# These locals defined here to avoid conflict with test framework
locals {
  firewall_private_ip = {
    for vnet_name, fw in azurerm_firewall.fw : vnet_name => fw.ip_configuration[0].private_ip_address
  }
  hub_routing = azurerm_route_table.hub_routing
  virtual_networks_modules = {
    for vnet_key, vnet_module in module.hub_virtual_networks : vnet_key => vnet_module
  }
}

# Create rgs as defined by var.hub_networks
resource "azurerm_resource_group" "rg" {
  for_each = { for rg in local.resource_group_data : rg.name => rg }

  location = each.value.location
  name     = each.key
  tags     = each.value.tags
}

resource "azurerm_management_lock" "rg_lock" {
  for_each = { for r in local.resource_group_data : r.name => r if r.lock }

  lock_level = "CanNotDelete"
  name       = coalesce(each.value.lock_name, substr("lock-${each.key}", 0, 90))
  scope      = azurerm_resource_group.rg[each.key].id
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
  virtual_network_dns_servers = each.value.dns_servers == null ? null : {
    dns_servers = each.value.dns_servers
  }
  virtual_network_flow_timeout_in_minutes = each.value.flow_timeout_in_minutes
  virtual_network_tags                    = each.value.tags
  subnets                                 = try(local.subnets_map[each.key], {})
}

resource "azurerm_virtual_network_peering" "hub_peering" {
  for_each = local.hub_peering_map

  name = each.key
  # added to make sure dependency graph is correct
  remote_virtual_network_id    = each.value.remote_virtual_network_id
  resource_group_name          = try(azurerm_resource_group.rg[var.hub_virtual_networks[each.value.src_key].resource_group_name].name, var.hub_virtual_networks[each.value.src_key].resource_group_name)
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
  resource_group_name           = try(azurerm_resource_group.rg[var.hub_virtual_networks[each.key].resource_group_name].name, var.hub_virtual_networks[each.key].resource_group_name)
  disable_bgp_route_propagation = false
  tags                          = {}

  route {
    address_prefix = "0.0.0.0/0"
    name           = "internet"
    next_hop_type  = "Internet"
  }
  dynamic "route" {
    for_each = toset(each.value.mesh_routes)

    content {
      address_prefix         = route.value.address_prefix
      name                   = route.value.name
      next_hop_in_ip_address = route.value.next_hop_ip_address
      next_hop_type          = route.value.next_hop_type
    }
  }
  dynamic "route" {
    for_each = toset(each.value.user_routes)

    content {
      address_prefix         = route.value.address_prefix
      name                   = route.value.name
      next_hop_in_ip_address = route.value.next_hop_ip_address
      next_hop_type          = route.value.next_hop_type
    }
  }
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

resource "azurerm_public_ip" "fw_default_ip_configuration_pip" {
  for_each = local.fw_default_ip_configuration_pip

  allocation_method   = "Static"
  location            = each.value.location
  name                = each.value.name
  resource_group_name = each.value.resource_group_name
  ip_version          = each.value.ip_version
  sku                 = "Standard"
  sku_tier            = each.value.sku_tier
  tags                = {}
  zones               = each.value.zones
}

resource "azurerm_subnet" "fw_subnet" {
  for_each = local.firewalls

  address_prefixes     = [each.value.subnet_address_prefix]
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.hub_virtual_networks[each.key].resource_group_name
  virtual_network_name = module.hub_virtual_networks[each.key].vnet_name
}

resource "azurerm_subnet_route_table_association" "fw_subnet_routing_creat" {
  for_each = { for vnet_name, fw in local.firewalls : vnet_name => fw if fw.subnet_route_table_id == null }

  route_table_id = azurerm_route_table.hub_routing[each.key].id
  subnet_id      = azurerm_subnet.fw_subnet[each.key].id
}

resource "azurerm_subnet_route_table_association" "fw_subnet_routing_external" {
  for_each = { for vnet_name, fw in local.firewalls : vnet_name => fw if fw.subnet_route_table_id != null }

  route_table_id = each.value.subnet_route_table_id
  subnet_id      = azurerm_subnet.fw_subnet[each.key].id
}

resource "azurerm_firewall" "fw" {
  for_each = local.firewalls

  location            = module.hub_virtual_networks[each.key].vnet_location
  name                = each.value.name
  resource_group_name = var.hub_virtual_networks[each.key].resource_group_name
  sku_name            = each.value.sku_name
  sku_tier            = each.value.sku_tier
  dns_servers         = each.value.dns_servers
  firewall_policy_id  = each.value.firewall_policy_id
  private_ip_ranges   = each.value.private_ip_ranges
  tags                = each.value.tags
  threat_intel_mode   = each.value.threat_intel_mode
  zones               = each.value.zones

  ip_configuration {
    name                 = each.value.default_ip_configuration.name
    public_ip_address_id = azurerm_public_ip.fw_default_ip_configuration_pip[each.key].id
    subnet_id            = azurerm_subnet.fw_subnet[each.key].id
  }
}
