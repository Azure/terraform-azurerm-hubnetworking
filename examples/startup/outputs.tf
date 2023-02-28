output "dashboard_pip" {
  value = azurerm_public_ip.dashboard.ip_address

  depends_on = [azurerm_linux_virtual_machine.dashboard]
}

output "counting_vm_ip" {
  value = azurerm_linux_virtual_machine.counting.private_ip_address
}
