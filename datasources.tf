data "azurerm_public_ip" "fw_additional_pip_guard" {
  for_each = local.fw_additional_pip_id

  # /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mygroup1/providers/Microsoft.Network/publicIPAddresses/myPublicIpAddress1
  name                = split("/", each.value)[8]
  resource_group_name = split("/", each.value)[4]
  lifecycle {
    postcondition {
      condition     = self.allocation_method == "Static" && self.sku == "Standard"
      error_message = "The Public IP for firewall must have a Static allocation and Standard SKU according to the [document](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall#public_ip_address_id)."
    }
  }
}