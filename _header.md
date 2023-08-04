# Terraform Verified Module for multi-hub network architectures

[![Average time to resolve an issue](http://isitmaintained.com/badge/resolution/Azure/terraform-azure-hubnetworking.svg)](http://isitmaintained.com/project/Azure/terraform-azure-hubnetworking "Average time to resolve an issue")
[![Percentage of issues still open](http://isitmaintained.com/badge/open/Azure/terraform-azure-hubnetworking.svg)](http://isitmaintained.com/project/Azure/terraform-azure-hubnetworking "Percentage of issues still open")

This module is designed to simplify the creation of multi-region hub networks in Azure. It will create a number of virtual networks and subnets, and optionally peer them together in a mesh topology with routing.

## Features

- This module will deploy `n` number of virtual networks and subnets.
Optionally, these virtual networks can be peered in a mesh topology.
- A routing address space can be specified for each hub network, this module will then create route tables for the other hub networks and associate them with the subnets.
- Azure Firewall can be deployed iun each hub network. This module will configure routing for the AzureFirewallSubnet.

## Example

```terraform
module "hubnetworks" {
  source  = "Azure/hubnetworking/azure"
  version = "<version>" # change this to your desired version, https://www.terraform.io/language/expressions/version-constraints

  hub_virtual_networks = {
    weu-hub = {
      name                  = "vnet-prod-weu-0001"
      address_space         = ["192.168.0.0/23"]
      routing_address_space = ["192.168.0.0/20"]
      firewall = {
        subnet_address_prefix = "192.168.1.0/24"
        sku_tier              = "Premium"
        sku_name              = "AZFW_VNet"
      }
    }
  }
}
```
