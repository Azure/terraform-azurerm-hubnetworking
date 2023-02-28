resource "random_pet" "rand" {}

module "hub_mesh" {
  source = "../.."
  hub_virtual_networks = {
    eastus-hub = {
      name                            = "eastus-hub"
      address_spaces                  = ["10.0.0.0/16"]
      location                        = "eastus"
      resource_group_name             = "hubandspokedemo-hub-eastus"
      resource_group_creation_enabled = true
      resource_group_lock_enabled     = false
      mesh_peering_enabled            = true
      routing_address_space           = ["10.0.0.0/16", "192.168.0.0/24"]
      subnets = {
        AzureFirewallSubnet = {
          address_prefixes = ["10.0.1.0/24"]
        }
      }
      firewall = {
        sku_name           = "AZFW_VNet"
        sku_tier           = "Standard"
        firewall_policy_id = azurerm_firewall_policy.fwpolicy.id
      }
    }
    eastus2-hub = {
      name                            = "eastus2-hub"
      address_spaces                  = ["10.1.0.0/16"]
      location                        = "eastus2"
      resource_group_name             = "hubandspokedemo-hub-eastus2"
      resource_group_creation_enabled = true
      resource_group_lock_enabled     = false
      mesh_peering_enabled            = true
      routing_address_space           = ["10.1.0.0/16", "192.168.1.0/24"]
      subnets = {
        AzureFirewallSubnet = {
          address_prefixes = ["10.1.1.0/24"]
        }
      }
      firewall = {
        sku_name           = "AZFW_VNet"
        sku_tier           = "Standard"
        firewall_policy_id = azurerm_firewall_policy.fwpolicy.id
      }
    }
  }
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename = "key.pem"
  content  = tls_private_key.key.private_key_pem
}

resource "azurerm_resource_group" "fwpolicy" {
  name     = "fwpolicy"
  location = "eastus"
}

resource "azurerm_firewall_policy" "fwpolicy" {
  name                = "allow-internal"
  resource_group_name = azurerm_resource_group.fwpolicy.name
  location            = azurerm_resource_group.fwpolicy.location
  sku                 = "Standard"
}

resource "azurerm_firewall_policy_rule_collection_group" "allow_internal" {
  name               = "allow-rfc1918"
  firewall_policy_id = azurerm_firewall_policy.fwpolicy.id
  priority           = 100

  network_rule_collection {
    action   = "Allow"
    name     = "rfc1918"
    priority = 100
    rule {
      name                  = "rfc1918"
      protocols             = ["Any"]
      source_addresses      = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      destination_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      destination_ports     = ["*"]
    }
  }
}


#resource "azurerm_public_ip" "fw" {
#  name                = "fw-pip"
#  resource_group_name = module.hub_mesh.resource_groups["hubandspokedemo-hub-eastus2"].name
#  location            = module.hub_mesh.resource_groups["hubandspokedemo-hub-eastus2"].location
#  allocation_method   = "Static"
#}
#
#resource "azurerm_network_interface" "fwmachine" {
#  name                = "fwmachine-nic"
#  location            = module.hub_mesh.resource_groups["hubandspokedemo-hub-eastus2"].location
#  resource_group_name = module.hub_mesh.resource_groups["hubandspokedemo-hub-eastus2"].name
#
#  ip_configuration {
#    name                          = "internal"
#    subnet_id                     = module.hub_mesh.virtual_networks["eastus2-hub"].subnets_name_id["fw"]
#    private_ip_address_allocation = "Dynamic"
#    public_ip_address_id          = azurerm_public_ip.fw.id
#  }
#}
#
#resource "azurerm_linux_virtual_machine" "fw" {
#  name                  = "fw-machine"
#  resource_group_name = module.hub_mesh.resource_groups["hubandspokedemo-hub-eastus2"].name
#  location            = module.hub_mesh.resource_groups["hubandspokedemo-hub-eastus2"].location
#  size                  = "Standard_F2"
#  admin_username        = "adminuser"
#  network_interface_ids = [
#    azurerm_network_interface.fwmachine.id,
#  ]
#
#  admin_ssh_key {
#    username   = "adminuser"
#    public_key = tls_private_key.key.public_key_openssh
#  }
#
#  os_disk {
#    caching              = "ReadWrite"
#    storage_account_type = "Standard_LRS"
#  }
#
#  source_image_reference {
#    publisher = "Canonical"
#    offer     = "UbuntuServer"
#    sku       = "16.04-LTS"
#    version   = "latest"
#  }
#}
#
#output "fwpip" {
#  value = azurerm_public_ip.fw.ip_address
#  depends_on = [azurerm_linux_virtual_machine.fw]
#}
