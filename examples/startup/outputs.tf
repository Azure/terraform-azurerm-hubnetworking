output "dashboard_pip" {
  value = azurerm_public_ip.dashboard.ip_address

  depends_on = [azurerm_linux_virtual_machine.dashboard]
}

output "dashboard_url" {
  value = "http://${azurerm_public_ip.dashboard.ip_address}:9002"
}

output "connectivity_test_url" {
  value = "http://${azurerm_public_ip.dashboard.ip_address}:8080"
}