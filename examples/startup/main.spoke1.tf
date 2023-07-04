resource "azurerm_resource_group" "spoke1" {
  location = "eastus"
  name     = "spoke1-${random_pet.rand.id}"
}

module "spoke1_vnet" {
  source  = "Azure/subnets/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.spoke1.name
  subnets = {
    spoke1-subnet = {
      address_prefixes = ["192.168.0.0/24"]
      route_table = {
        id = azurerm_route_table.spoke1.id
      }
    }
  }
  virtual_network_address_space = ["192.168.0.0/24"]
  virtual_network_location      = azurerm_resource_group.spoke1.location
  virtual_network_name          = "spoke1-vnet-${random_pet.rand.id}"
}

resource "azurerm_route_table" "spoke1" {
  location            = azurerm_resource_group.spoke1.location
  name                = "spoke1-rt"
  resource_group_name = azurerm_resource_group.spoke1.name
}

resource "azurerm_route" "spoke1_to_hub" {
  address_prefix         = "192.168.0.0/16"
  name                   = "to-hub"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.spoke1.name
  route_table_name       = azurerm_route_table.spoke1.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus-hub"].hub_router_ip_address
}

resource "azurerm_route" "spoke1_to_hub2" {
  address_prefix         = "10.0.0.0/8"
  name                   = "to-hub2"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.spoke1.name
  route_table_name       = azurerm_route_table.spoke1.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus-hub"].hub_router_ip_address
}

resource "azurerm_virtual_network_peering" "spoke1_peering" {
  name                         = "spoke1-peering"
  remote_virtual_network_id    = module.hub_mesh.virtual_networks["eastus-hub"].id
  resource_group_name          = azurerm_resource_group.spoke1.name
  virtual_network_name         = module.spoke1_vnet.vnet_name
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke1_peering_back" {
  name                         = "spoke1-peering-back"
  remote_virtual_network_id    = module.spoke1_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus-hub"].name
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_network_interface" "spoke1" {
  location            = azurerm_resource_group.spoke1.location
  name                = "spoke1-machine-nic"
  resource_group_name = azurerm_resource_group.spoke1.name

  ip_configuration {
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = module.spoke1_vnet.vnet_subnets_name_id["spoke1-subnet"]
  }
}

resource "azurerm_linux_virtual_machine" "spoke1" {
  #checkov:skip=CKV_AZURE_50:Only for connectivity test so we use vm extension
  #checkov:skip=CKV_AZURE_179:Only for connectivity test so we use vm extension
  admin_username = "adminuser"
  location       = azurerm_resource_group.spoke1.location
  name           = "spoke1-machine"
  network_interface_ids = [
    azurerm_network_interface.spoke1.id,
  ]
  resource_group_name = azurerm_resource_group.spoke1.name
  size                = "Standard_B2ms"


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  admin_ssh_key {
    public_key = tls_private_key.key.public_key_openssh
    username   = "adminuser"
  }
  source_image_reference {
    offer     = "0001-com-ubuntu-server-jammy"
    publisher = "Canonical"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
