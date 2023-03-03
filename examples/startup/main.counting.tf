resource "azurerm_resource_group" "counting" {
  location = "eastus"
  name     = "counting-${random_pet.rand.id}"
}

module "counting_vnet" {
  source  = "Azure/subnets/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.counting.name
  subnets = {
    counting-subnet = {
      address_prefixes = ["192.168.0.0/24"]
      route_table = {
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
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.counting.name
  route_table_name       = azurerm_route_table.counting.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus-hub"].hub_router_ip_address
}

resource "azurerm_route" "counting_to_hub2" {
  address_prefix         = "10.0.0.0/8"
  name                   = "to-hub2"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.counting.name
  route_table_name       = azurerm_route_table.counting.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus-hub"].hub_router_ip_address
}

resource "azurerm_virtual_network_peering" "counting_peering" {
  name                         = "counting-peering"
  remote_virtual_network_id    = module.hub_mesh.virtual_networks["eastus-hub"].id
  resource_group_name          = azurerm_resource_group.counting.name
  virtual_network_name         = module.counting_vnet.vnet_name
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "counting_peering_back" {
  name                         = "counting-peering-back"
  remote_virtual_network_id    = module.counting_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus-hub"].name
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_network_interface" "counting" {
  location            = azurerm_resource_group.counting.location
  name                = "counting-nic"
  resource_group_name = azurerm_resource_group.counting.name

  ip_configuration {
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = module.counting_vnet.vnet_subnets_name_id["counting-subnet"]
  }
}

resource "azurerm_linux_virtual_machine" "counting" {
  #checkov:skip=CKV_AZURE_50:Only for connectivity test so we use vm extension
  admin_username      = "adminuser"
  location            = azurerm_resource_group.counting.location
  name                = "counting-machine"
  network_interface_ids = [
    azurerm_network_interface.counting.id,
  ]
  resource_group_name = azurerm_resource_group.counting.name
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

resource "azurerm_virtual_machine_extension" "start_counting" {
  name                 = "start-svc"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  virtual_machine_id   = azurerm_linux_virtual_machine.counting.id
  settings = jsonencode({
    commandToExecute = "curl -sSL https://get.docker.com/ | sh && sudo docker run -d --restart=always -p 9001:9001 hashicorp/counting-service:0.0.2 && sudo docker run -d --restart=always -p 5678:5678 hashicorp/http-echo -text='hello world'"
  })
}