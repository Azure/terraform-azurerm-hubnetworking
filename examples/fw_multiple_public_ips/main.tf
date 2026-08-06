locals {
  regions = toset(["eastus", "eastus2"])
}

resource "azurerm_resource_group" "hub_rg" {
  for_each = local.regions

  location = each.value
  name     = "hubandspokedemo-hub-${each.value}-${random_pet.rand.id}"
}

resource "random_pet" "rand" {}

resource "azurerm_public_ip" "extra" {
  for_each = local.regions

  allocation_method   = "Static"
  location            = azurerm_resource_group.hub_rg[each.value].location
  name                = "extrapip-${each.value}"
  resource_group_name = azurerm_resource_group.hub_rg[each.value].name
  sku                 = "Standard"
}

module "hub_mesh" {
  source = "../.."
  hub_virtual_networks = {
    eastus-hub = {
      name                            = "eastus-hub"
      address_space                   = ["10.0.0.0/16"]
      location                        = "eastus"
      resource_group_name             = azurerm_resource_group.hub_rg["eastus"].name
      resource_group_creation_enabled = false
      resource_group_lock_enabled     = false
      mesh_peering_enabled            = true
      route_table_name                = "contosohotel-eastus-hub-rt"
      routing_address_space           = ["10.0.0.0/16", "192.168.0.0/24"]
      firewall = {
        sku_name              = "AZFW_VNet"
        sku_tier              = "Standard"
        subnet_address_prefix = "10.0.1.0/24"
        firewall_policy_id    = azurerm_firewall_policy.fwpolicy.id
        additional_ip_configurations = {
          additional = {
            name                 = "pip-${random_pet.rand.id}"
            public_ip_address_id = azurerm_public_ip.extra["eastus"].id
          }
        }
      }
    }
    eastus2-hub = {
      name                            = "eastus2-hub"
      address_space                   = ["10.1.0.0/16"]
      location                        = "eastus2"
      resource_group_name             = azurerm_resource_group.hub_rg["eastus2"].name
      resource_group_creation_enabled = false
      resource_group_lock_enabled     = false
      mesh_peering_enabled            = true
      route_table_name                = "contoso-eastus2-hub-rt"
      routing_address_space           = ["10.1.0.0/16", "192.168.1.0/24"]
      firewall = {
        sku_name              = "AZFW_VNet"
        sku_tier              = "Standard"
        subnet_address_prefix = "10.1.1.0/24"
        firewall_policy_id    = azurerm_firewall_policy.fwpolicy.id
        additional_ip_configurations = {
          additional = {
            name                 = "pip-${random_pet.rand.id}"
            public_ip_address_id = azurerm_public_ip.extra["eastus2"].id
          }
        }
      }
    }
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.allow_internal]
}

resource "azurerm_resource_group" "fwpolicy" {
  location = "eastus"
  name     = "fwpolicy-${random_pet.rand.id}"
}

resource "azurerm_firewall_policy" "fwpolicy" {
  location            = azurerm_resource_group.fwpolicy.location
  name                = "allow-internal"
  resource_group_name = azurerm_resource_group.fwpolicy.name
  sku                 = "Standard"
}

resource "azurerm_firewall_policy_rule_collection_group" "allow_internal" {
  firewall_policy_id = azurerm_firewall_policy.fwpolicy.id
  name               = "allow-rfc1918"
  priority           = 100

  network_rule_collection {
    action   = "Allow"
    name     = "rfc1918"
    priority = 100

    rule {
      destination_ports     = ["*"]
      name                  = "rfc1918"
      protocols             = ["Any"]
      destination_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      source_addresses      = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    }
  }
}
