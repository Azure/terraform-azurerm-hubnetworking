resource "azurerm_resource_group" "spoke2" {
  location = "eastus2"
  name     = "spoke2-${random_pet.rand.id}"
}

module "spoke2_vnet" {
  source  = "Azure/subnets/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.spoke2.name
  subnets = {
    spoke2-subnet = {
      address_prefixes = ["192.168.1.0/24"]
      route_table = {
        id = azurerm_route_table.spoke2.id
      }
    }
  }
  virtual_network_address_space = ["192.168.1.0/24"]
  virtual_network_location      = azurerm_resource_group.spoke2.location
  virtual_network_name          = "spoke2-vnet-${random_pet.rand.id}"
}

resource "azurerm_route_table" "spoke2" {
  location            = azurerm_resource_group.spoke2.location
  name                = "spoke2-rt"
  resource_group_name = azurerm_resource_group.spoke2.name
}

resource "azurerm_route" "spoke2_to_hub" {
  address_prefix         = "192.168.0.0/16"
  name                   = "to-hub"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.spoke2.name
  route_table_name       = azurerm_route_table.spoke2.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus2-hub"].hub_router_ip_address
}

resource "azurerm_route" "spoke2_to_hub2" {
  address_prefix         = "10.0.0.0/8"
  name                   = "to-hub2"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.spoke2.name
  route_table_name       = azurerm_route_table.spoke2.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus2-hub"].hub_router_ip_address
}

resource "azurerm_virtual_network_peering" "spoke2_peering" {
  name                         = "spoke2-peering"
  remote_virtual_network_id    = module.hub_mesh.virtual_networks["eastus2-hub"].id
  resource_group_name          = azurerm_resource_group.spoke2.name
  virtual_network_name         = module.spoke2_vnet.vnet_name
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke2_peering_back" {
  name                         = "spoke2-peering-back"
  remote_virtual_network_id    = module.spoke2_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus2-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus2-hub"].name
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_public_ip" "spoke2" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.spoke2.location
  name                = "vm1-pip"
  resource_group_name = azurerm_resource_group.spoke2.name
}

resource "azurerm_network_interface" "spoke2" {
  #checkov:skip=CKV_AZURE_119:It's only for connectivity test
  location            = azurerm_resource_group.spoke2.location
  name                = "spoke2-machine-nic"
  resource_group_name = azurerm_resource_group.spoke2.name

  ip_configuration {
    name                          = "nic"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.spoke2.id
    subnet_id                     = module.spoke2_vnet.vnet_subnets_name_id["spoke2-subnet"]
  }
}

resource "azurerm_linux_virtual_machine" "spoke2" {
  #checkov:skip=CKV_AZURE_50:Only for connectivity test so we use vm extension
  #checkov:skip=CKV_AZURE_179:Only for connectivity test so we use vm extension
  admin_username = "adminuser"
  location       = azurerm_resource_group.spoke2.location
  name           = "spoke2-machine"
  network_interface_ids = [
    azurerm_network_interface.spoke2.id,
  ]
  resource_group_name = azurerm_resource_group.spoke2.name
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
