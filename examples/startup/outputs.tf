output "spoke2_pip" {
  value = azurerm_public_ip.spoke2.ip_address

  depends_on = [azurerm_linux_virtual_machine.spoke2]
}
