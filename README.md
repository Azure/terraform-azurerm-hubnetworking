<!-- BEGIN_TF_DOCS -->
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

## Documentation
<!-- markdownlint-disable MD033 -->

## Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) (>= 1.3.0)

- <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) (>= 3.7.0, < 4.0)

## Modules

The following Modules are called:

### <a name="module_hub_virtual_networks"></a> [hub\_virtual\_networks](#module\_hub\_virtual\_networks)

Source: Azure/subnets/azurerm

Version: 1.0.0

<!-- markdownlint-disable MD013 -->
## Required Inputs

No required inputs.

## Optional Inputs

The following input variables are optional (have default values):

### <a name="input_hub_virtual_networks"></a> [hub\_virtual\_networks](#input\_hub\_virtual\_networks)

Description: A map of the hub virtual networks to create. The map key is an arbitrary value to avoid Terraform's restriction that map keys must be known at plan time.

### Mandatory fields

- `name` - The name of the Virtual Network.
- `address_space` - A list of IPv4 address spaces that are used by this virtual network in CIDR format, e.g. `["192.168.0.0/24"]`.
- `location` - The Azure location where the virtual network should be created.
- `resource_group_name` - The name of the resource group in which the virtual network should be created.

### Optional fields

- `bgp_community` - The BGP community associated with the virtual network.
- `ddos_protection_plan_id` - The ID of the DDoS protection plan associated with the virtual network.
- `dns_servers` - A list of DNS servers IP addresses for the virtual network.
- `flow_timeout_in_minutes` - The flow timeout in minutes for the virtual network. Default `4`.
- `mesh_peering_enabled` - Should the virtual network be peered to other hub networks with this flag enabled? Default `true`.
- `resource_group_creation_enabled` - Should the resource group for this virtual network be created by this module? Default `true`.
- `resource_group_lock_enabled` - Should the resource group for this virtual network be locked? Default `true`.
- `resource_group_lock_name` - The name of the resource group lock.
- `resource_group_tags` - A map of tags to apply to the resource group.
- `routing_address_space` - A list of IPv4 address spaces in CIDR format that are used for routing to this hub, e.g. `["192.168.0.0","172.16.0.0/12"]`.
- `hub_router_ip_address` - If not using Azure Firewall, this is the IP address of the hub router. This is used to create route table entries for other hub networks.
- `tags` - A map of tags to apply to the virtual network.

#### Route table entries

- `route_table_entries` - (Optional) A set of additional route table entries to add to the route table for this hub network. Default empty `[]`. The value is an object with the following fields:
  - `name` - The name of the route table entry.
  - `address_prefix` - The address prefix to match for this route table entry.
  - `next_hop_type` - The type of the next hop. Possible values include `Internet`, `VirtualAppliance`, `VirtualNetworkGateway`, `VnetLocal`, `None`.
  - `has_bgp_override` - Should the BGP override be enabled for this route table entry? Default `false`.
  - `next_hop_ip_address` - The IP address of the next hop. Required if `next_hop_type` is `VirtualAppliance`.

#### Subnets

- `subnets` - (Optional) A map of subnets to create in the virtual network. The value is an object with the following fields:
  - `address_prefixes` - The IPv4 address prefixes to use for the subnet in CIDR format.
  - `nat_gateway` - (Optional) An object with the following fields:
    - `id` - The ID of the NAT Gateway which should be associated with the Subnet. Changing this forces a new resource to be created.
  - `network_security_group` - (Optional) An object with the following fields:
    - `id` - The ID of the Network Security Group which should be associated with the Subnet. Changing this forces a new association to be created.
  - `private_endpoint_network_policies_enabled` - (Optional) Enable or Disable network policies for the private endpoint on the subnet. Setting this to true will Enable the policy and setting this to false will Disable the policy. Defaults to true.
  - `private_link_service_network_policies_enabled` - (Optional) Enable or Disable network policies for the private link service on the subnet. Setting this to true will Enable the policy and setting this to false will Disable the policy. Defaults to true.
  - `assign_generated_route_table` - (Optional) Should the Route Table generated by this module be associated with this Subnet? Default `true`. Cannot be used with `external_route_table_id`.
  - `external_route_table_id` - (Optional) The ID of the Route Table which should be associated with the Subnet. Changing this forces a new association to be created. Cannot be used with `assign_generated_route_table`.
  - `service_endpoints` - (Optional) The list of Service endpoints to associate with the subnet.
  - `service_endpoint_policy_ids` - (Optional) The list of Service Endpoint Policy IDs to associate with the subnet.
  - `service_endpoint_policy_assignment_enabled` - (Optional) Should the Service Endpoint Policy be assigned to the subnet? Default `true`.
  - `delegation` - (Optional) An object with the following fields:
    - `name` - The name of the delegation.
    - `service_delegation` - An object with the following fields:
      - `name` - The name of the service delegation.
      - `actions` - A list of actions that should be delegated, the list is specific to the service being delegated.

#### Azure Firewall

- `firewall` - (Optional) An object with the following fields:
  - `sku_name` - The name of the SKU to use for the Azure Firewall. Possible values include `AZFW_Hub`, `AZFW_VNet`.
  - `sku_tier` - The tier of the SKU to use for the Azure Firewall. Possible values include `Basic`, `Standard`, `Premium`.
  - `subnet_address_prefix` - The IPv4 address prefix to use for the Azure Firewall subnet in CIDR format. Needs to be a part of the virtual network's address space.
  - `dns_servers` - (Optional) A list of DNS server IP addresses for the Azure Firewall.
  - `firewall_policy_id` - (Optional) The resource id of the Azure Firewall Policy to associate with the Azure Firewall.
  - `management_subnet_address_prefix` - (Optional) The IPv4 address prefix to use for the Azure Firewall management subnet in CIDR format. Needs to be a part of the virtual network's address space.
  - `name` - (Optional) The name of the firewall resource. If not specified will use `afw-{vnetname}`.
  - `private_ip_ranges` - (Optional) A list of private IP ranges to use for the Azure Firewall, to which the firewall will not NAT traffic. If not specified will use RFC1918.
  - `subnet_route_table_id` = (Optional) The resource id of the Route Table which should be associated with the Azure Firewall subnet. If not specified the module will assign the generated route table.
  - `tags` - (Optional) A map of tags to apply to the Azure Firewall. If not specified
  - `threat_intel_mode` - (Optional) The threat intelligence mode for the Azure Firewall. Possible values include `Alert`, `Deny`, `Off`.
  - `zones` - (Optional) A list of availability zones to use for the Azure Firewall. If not specified will be `null`.
  - `default_ip_configuration` - (Optional) An object with the following fields. If not specified the defaults below will be used:
    - `name` - (Optional) The name of the default IP configuration. If not specified will use `default`.
    - `public_ip_config` - (Optional) An object with the following fields:
      - `name` - (Optional) The name of the public IP configuration. If not specified will use `pip-afw-{vnetname}`.
      - `zones` - (Optional) A list of availability zones to use for the public IP configuration. If not specified will be `null`.
      - `ip_version` - (Optional) The IP version to use for the public IP configuration. Possible values include `IPv4`, `IPv6`. If not specified will be `IPv4`.
      - `sku_tier` - (Optional) The SKU tier to use for the public IP configuration. Possible values include `Regional`, `Global`. If not specified will be `Regional`.
  - `management_ip_configuration` - (Optional) An object with the following fields. If not specified the defaults below will be used:
    - `name` - (Optional) The name of the management IP configuration. If not specified will use `defaultMgmt`.
    - `public_ip_config` - (Optional) An object with the following fields:
      - `name` - (Optional) The name of the public IP configuration. If not specified will use `pip-afw-mgmt-<Map Key>`.
      - `zones` - (Optional) A list of availability zones to use for the public IP configuration. If not specified will be `null`.
      - `ip_version` - (Optional) The IP version to use for the public IP configuration. Possible values include `IPv4`, `IPv6`. If not specified will be `IPv4`.
      - `sku_tier` - (Optional) The SKU tier to use for the public IP configuration. Possible values include `Regional`, `Global`. If not specified will be `Regional`.

Type:

```hcl
map(object({
    name                            = string
    address_space                   = list(string)
    location                        = string
    resource_group_name             = string
    route_table_name                = optional(string)
    bgp_community                   = optional(string)
    ddos_protection_plan_id         = optional(string)
    dns_servers                     = optional(list(string))
    flow_timeout_in_minutes         = optional(number, 4)
    mesh_peering_enabled            = optional(bool, true)
    resource_group_creation_enabled = optional(bool, true)
    resource_group_lock_enabled     = optional(bool, true)
    resource_group_lock_name        = optional(string)
    resource_group_tags             = optional(map(string))
    routing_address_space           = optional(list(string), [])
    hub_router_ip_address           = optional(string)
    tags                            = optional(map(string), {})

    route_table_entries = optional(set(object({
      name           = string
      address_prefix = string
      next_hop_type  = string

      has_bgp_override    = optional(bool, false)
      next_hop_ip_address = optional(string)
    })), [])

    subnets = optional(map(object(
      {
        address_prefixes = list(string)
        nat_gateway = optional(object({
          id = string
        }))
        network_security_group = optional(object({
          id = string
        }))
        private_endpoint_network_policies_enabled     = optional(bool, true)
        private_link_service_network_policies_enabled = optional(bool, true)
        assign_generated_route_table                  = optional(bool, true)
        external_route_table_id                       = optional(string)
        service_endpoints                             = optional(set(string))
        service_endpoint_policy_ids                   = optional(set(string))
        delegations = optional(list(
          object(
            {
              name = string
              service_delegation = object({
                name    = string
                actions = optional(list(string))
              })
            }
          )
        ))
      }
    )), {})

    firewall = optional(object({
      sku_name                         = string
      sku_tier                         = string
      subnet_address_prefix            = string
      dns_servers                      = optional(list(string))
      firewall_policy_id               = optional(string)
      management_subnet_address_prefix = optional(string, null)
      name                             = optional(string)
      private_ip_ranges                = optional(list(string))
      subnet_route_table_id            = optional(string)
      tags                             = optional(map(string))
      threat_intel_mode                = optional(string, "Alert")
      zones                            = optional(list(string))
      default_ip_configuration = optional(object({
        name = optional(string)
        public_ip_config = optional(object({
          ip_version = optional(string)
          name       = optional(string)
          sku_tier   = optional(string, "Regional")
          zones      = optional(set(string))
        }))
      }))
      management_ip_configuration = optional(object({
        name = optional(string)
        public_ip_config = optional(object({
          ip_version = optional(string)
          name       = optional(string)
          sku_tier   = optional(string, "Regional")
          zones      = optional(set(string))
        }))
      }))
    }))
  }))
```

Default: `{}`

### <a name="input_tracing_tags_enabled"></a> [tracing\_tags\_enabled](#input\_tracing\_tags\_enabled)

Description: Whether enable tracing tags that generated by BridgeCrew Yor.

Type: `bool`

Default: `false`

### <a name="input_tracing_tags_prefix"></a> [tracing\_tags\_prefix](#input\_tracing\_tags\_prefix)

Description: Default prefix for generated tracing tags

Type: `string`

Default: `"avm_"`

## Resources

The following resources are used by this module:

- [azurerm_firewall.fw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall) (resource)
- [azurerm_management_lock.rg_lock](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) (resource)
- [azurerm_public_ip.fw_default_ip_configuration_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) (resource)
- [azurerm_public_ip.fw_management_ip_configuration_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) (resource)
- [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) (resource)
- [azurerm_route_table.hub_routing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) (resource)
- [azurerm_subnet.fw_management_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) (resource)
- [azurerm_subnet.fw_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) (resource)
- [azurerm_subnet_route_table_association.fw_subnet_routing_creat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) (resource)
- [azurerm_subnet_route_table_association.fw_subnet_routing_external](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) (resource)
- [azurerm_subnet_route_table_association.hub_routing_creat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) (resource)
- [azurerm_subnet_route_table_association.hub_routing_external](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) (resource)
- [azurerm_virtual_network_peering.hub_peering](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) (resource)

## Outputs

The following outputs are exported:

### <a name="output_firewalls"></a> [firewalls](#output\_firewalls)

Description: A curated output of the firewalls created by this module.

### <a name="output_hub_route_tables"></a> [hub\_route\_tables](#output\_hub\_route\_tables)

Description: A curated output of the route tables created by this module.

### <a name="output_resource_groups"></a> [resource\_groups](#output\_resource\_groups)

Description: A curated output of the resource groups created by this module.

### <a name="output_virtual_networks"></a> [virtual\_networks](#output\_virtual\_networks)

Description: A curated output of the virtual networks created by this module.

<!-- markdownlint-enable -->
## Enable or disable tracing tags

We're using [BridgeCrew Yor](https://github.com/bridgecrewio/yor) and [yorbox](https://github.com/lonegunmanb/yorbox) to help manage tags consistently across infrastructure as code (IaC) frameworks. In this module you might see tags like:

```hcl
resource "azurerm_resource_group" "rg" {
  location = "eastus"
  name     = random_pet.name
  tags = merge(var.tags, (/*<box>*/ (var.tracing_tags_enabled ? { for k, v in /*</box>*/ {
    avm_git_commit           = "3077cc6d0b70e29b6e106b3ab98cee6740c916f6"
    avm_git_file             = "main.tf"
    avm_git_last_modified_at = "2023-05-05 08:57:54"
    avm_git_org              = "lonegunmanb"
    avm_git_repo             = "terraform-yor-tag-test-module"
    avm_yor_trace            = "a0425718-c57d-401c-a7d5-f3d88b2551a4"
  } /*<box>*/ : replace(k, "avm_", var.tracing_tags_prefix) => v } : {}) /*</box>*/))
}
```

To enable tracing tags, set the variable to true:

```hcl
module "example" {
  source               = <module_source>
  ...
  tracing_tags_enabled = true
}
```

The `tracing_tags_enabled` is default to `false`.

To customize the prefix for your tracing tags, set the `tracing_tags_prefix` variable value in your Terraform configuration:

```hcl
module "example" {
  source              = <module_source>
  ...
  tracing_tags_prefix = "custom_prefix_"
}
```

The actual applied tags would be:

```text
{
  custom_prefix_git_commit           = "3077cc6d0b70e29b6e106b3ab98cee6740c916f6"
  custom_prefix_git_file             = "main.tf"
  custom_prefix_git_last_modified_at = "2023-05-05 08:57:54"
  custom_prefix_git_org              = "lonegunmanb"
  custom_prefix_git_repo             = "terraform-yor-tag-test-module"
  custom_prefix_yor_trace            = "a0425718-c57d-401c-a7d5-f3d88b2551a4"
}
```

<!-- markdownlint-disable MD041 -->
## Contributing
<!-- markdownlint-enable -->

This project welcomes contributions and suggestions.
Most contributions require you to agree to a Contributor License Agreement (CLA)
declaring that you have the right to, and actually do, grant us the rights to use your contribution.
For details, visit [https://cla.opensource.microsoft.com](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment).
Simply follow the instructions provided by the bot.
You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services.
Authorized use of Microsoft trademarks or logos is subject to and must follow Microsoft's Trademark & Brand Guidelines.
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
<!-- END_TF_DOCS -->