resource "azurerm_resource_group" "dashboard" {
  location = "eastus2"
  name     = "dashboard-${random_pet.rand.id}"
}

module "dashboard_vnet" {
  source  = "Azure/subnets/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.dashboard.name
  subnets = {
    dashboard-subnet = {
      address_prefixes = ["192.168.1.0/24"]
      route_table = {
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

resource "azurerm_route" "dashboard_to_hub" {
  address_prefix         = "192.168.0.0/16"
  name                   = "to-hub"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.dashboard.name
  route_table_name       = azurerm_route_table.dashboard.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus2-hub"].hub_router_ip_address
}

resource "azurerm_route" "dashboard_to_hub2" {
  address_prefix         = "10.0.0.0/8"
  name                   = "to-hub2"
  next_hop_type          = "VirtualAppliance"
  resource_group_name    = azurerm_resource_group.dashboard.name
  route_table_name       = azurerm_route_table.dashboard.name
  next_hop_in_ip_address = module.hub_mesh.virtual_networks["eastus2-hub"].hub_router_ip_address
}

resource "azurerm_virtual_network_peering" "dashboard_peering" {
  name                         = "dashboard-peering"
  remote_virtual_network_id    = module.hub_mesh.virtual_networks["eastus2-hub"].id
  resource_group_name          = azurerm_resource_group.dashboard.name
  virtual_network_name         = module.dashboard_vnet.vnet_name
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "dashboard_peering_back" {
  name                         = "dashboard-peering-back"
  remote_virtual_network_id    = module.dashboard_vnet.vnet_id
  resource_group_name          = module.hub_mesh.virtual_networks["eastus2-hub"].resource_group_name
  virtual_network_name         = module.hub_mesh.virtual_networks["eastus2-hub"].name
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_public_ip" "dashboard" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.dashboard.location
  name                = "dashboard-pip"
  resource_group_name = azurerm_resource_group.dashboard.name
}

resource "azurerm_network_interface" "dashboard" {
  #checkov:skip=CKV_AZURE_119:It's only for connectivity test
  location            = azurerm_resource_group.dashboard.location
  name                = "dashboard-nic"
  resource_group_name = azurerm_resource_group.dashboard.name

  ip_configuration {
    name                          = "nic"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.dashboard.id
    subnet_id                     = module.dashboard_vnet.vnet_subnets_name_id["dashboard-subnet"]
  }
}

resource "azurerm_linux_virtual_machine" "dashboard" {
  #checkov:skip=CKV_AZURE_50:Only for connectivity test so we use vm extension
  admin_username = "adminuser"
  location       = azurerm_resource_group.dashboard.location
  name           = "dashboard-machine"
  network_interface_ids = [
    azurerm_network_interface.dashboard.id,
  ]
  resource_group_name = azurerm_resource_group.dashboard.name
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

resource "azurerm_virtual_machine_extension" "start_dashboard" {
  name                 = "start-svc"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  virtual_machine_id   = azurerm_linux_virtual_machine.dashboard.id
  settings = jsonencode({
    commandToExecute = "curl -sSL https://get.docker.com/ | sh && sudo docker run -d --restart=always -p 9002:9002 -e COUNTING_SERVICE_URL='http://${azurerm_linux_virtual_machine.counting.private_ip_address}:9001' hashicorp/dashboard-service:0.0.4 && sudo docker run -d --restart=always -p 8080:5678 hpello/tcp-proxy ${azurerm_linux_virtual_machine.counting.private_ip_address} 5678"
  })
}