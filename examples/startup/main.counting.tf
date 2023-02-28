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

resource "azurerm_route" "counting_to_hub" {
  address_prefix         = "192.168.0.0/16"
  name                   = "to-hub"
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus-hub"].hub_router_ip_address
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.counting.name
  route_table_name       = azurerm_route_table.counting.name
}

resource "azurerm_route" "counting_to_hub2" {
  address_prefix         = "10.0.0.0/8"
  name                   = "to-hub2"
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
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "counting_peering_back" {
  name                         = "counting-peering-back"
  remote_virtual_network_id    = module.counting_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus-hub"].name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
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
  name                  = "counting-machine"
  resource_group_name   = azurerm_resource_group.counting.name
  location              = azurerm_resource_group.counting.location
  size                  = "Standard_B2ms"
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
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
