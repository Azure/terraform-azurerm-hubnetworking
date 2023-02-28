resource "random_pet" "rand" {}

module "hub_mesh" {
  source               = "../.."
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
      subnets                         = {
        AzureFirewallSubnet = {
          address_prefixes = ["10.0.1.0/24"]
        }
      }
      firewall = {
        sku_name = "AZFW_VNet"
        sku_tier = "Standard"
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
      subnets                         = {
        AzureFirewallSubnet = {
          address_prefixes = ["10.1.1.0/24"]
        }
      }
      firewall = {
        sku_name = "AZFW_VNet"
        sku_tier = "Standard"
      }
    }
  }
}

resource "azurerm_resource_group" "counting" {
  location = "eastus"
  name     = "counting-${random_pet.rand.id}"
}

module "counting_vnet" {
  source  = "Azure/subnets/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.counting.name
  subnets             = {
    counting-subnet = {
      address_prefixes = ["192.168.0.0/24"]
      route_table      = {
        id = azurerm_route_table.counting.id
      }
    }
  }
  virtual_network_address_space = ["192.168.0.0/24"]
  virtual_network_location      = azurerm_resource_group.counting.location
  virtual_network_name          = "counting-vnet-${random_pet.rand.id}"
}

resource "azurerm_route_table" "counting" {
  location            = azurerm_resource_group.counting.location
  name                = "counting-rt"
  resource_group_name = azurerm_resource_group.counting.name
}

resource "azurerm_route" "to_dashboard" {
  address_prefix         = "0.0.0.0/0"
  name                   = "to-dashboard"
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus-hub"].hub_router_ip_address
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.counting.name
  route_table_name       = azurerm_route_table.counting.name
}

resource "azurerm_virtual_network_peering" "counting_peering" {
  name                         = "counting-peering"
  remote_virtual_network_id    = module.hub_mesh.virtual_networks["eastus-hub"].id
  resource_group_name          = azurerm_resource_group.counting.name
  virtual_network_name         = module.counting_vnet.vnet_name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "counting_peering_back" {
  name                         = "counting-peering-back"
  remote_virtual_network_id    = module.counting_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus-hub"].name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_resource_group" "dashboard" {
  location = "eastus2"
  name     = "dashboard-${random_pet.rand.id}"
}

module "dashboard_vnet" {
  source  = "Azure/subnets/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.dashboard.name
  subnets             = {
    dashboard-subnet = {
      address_prefixes = ["192.168.1.0/24"]
      route_table      = {
        id = azurerm_route_table.dashboard.id
      }
    }
  }
  virtual_network_address_space = ["192.168.1.0/24"]
  virtual_network_location      = azurerm_resource_group.dashboard.location
  virtual_network_name          = "dashboard-vnet-${random_pet.rand.id}"
}

resource "azurerm_route_table" "dashboard" {
  location            = azurerm_resource_group.dashboard.location
  name                = "dashboard-rt"
  resource_group_name = azurerm_resource_group.dashboard.name
}

resource "azurerm_route" "to_counting" {
  address_prefix         = "192.168.0.0/16"
  name                   = "to-counting"
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus2-hub"].hub_router_ip_address
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.dashboard.name
  route_table_name       = azurerm_route_table.dashboard.name
}

resource "azurerm_route" "to_counting2" {
  address_prefix         = "10.0.0.0/8"
  name                   = "to-counting2"
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus2-hub"].hub_router_ip_address
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.dashboard.name
  route_table_name       = azurerm_route_table.dashboard.name
}


resource "azurerm_virtual_network_peering" "dashboard_peering" {
  name                         = "dashboard-peering"
  remote_virtual_network_id    = module.hub_mesh.virtual_networks["eastus2-hub"].id
  resource_group_name          = azurerm_resource_group.dashboard.name
  virtual_network_name         = module.dashboard_vnet.vnet_name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "dashboard_peering_back" {
  name                         = "dashboard-peering-back"
  remote_virtual_network_id    = module.dashboard_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus2-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus2-hub"].name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename = "key.pem"
  content  = tls_private_key.key.private_key_pem
}

resource "azurerm_network_interface" "counting" {
  name                = "counting-nic"
  location            = azurerm_resource_group.counting.location
  resource_group_name = azurerm_resource_group.counting.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.counting_vnet.vnet_subnets_name_id["counting-subnet"]
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "counting" {
  name                  = "example-machine"
  resource_group_name   = azurerm_resource_group.counting.name
  location              = azurerm_resource_group.counting.location
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.counting.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

resource "azurerm_public_ip" "dashboard" {
  name                = "dashboard-pip"
  resource_group_name = azurerm_resource_group.dashboard.name
  location            = azurerm_resource_group.dashboard.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "dashboard" {
  name                = "dashboard-nic"
  location            = azurerm_resource_group.dashboard.location
  resource_group_name = azurerm_resource_group.dashboard.name

  ip_configuration {
    name                          = "nic"
    subnet_id                     = module.dashboard_vnet.vnet_subnets_name_id["dashboard-subnet"]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.dashboard.id
  }
}

resource "azurerm_linux_virtual_machine" "dashboard" {
  name                  = "dashboard-machine"
  resource_group_name   = azurerm_resource_group.dashboard.name
  location              = azurerm_resource_group.dashboard.location
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.dashboard.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

output "dashboard_pip" {
  value = azurerm_public_ip.dashboard.ip_address

  depends_on = [azurerm_linux_virtual_machine.dashboard]
}

output "counting_vm_ip" {
  value = azurerm_linux_virtual_machine.counting.private_ip_address
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