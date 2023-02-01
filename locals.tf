locals {
  # Logic to determine the number of peerings to create for all hub networks with mesh_peering enabled.
  hub_peering_map = {
    for peerconfig in flatten([
      for k_src, v_src in var.hub_virtual_networks :
      [
        for k_dst, v_dst in var.hub_virtual_networks :
        {
          name                         = "${k_src}-${k_dst}"
          remote_virtual_network_id    = module.hub_virtual_networks[k2].vnet_id
          allow_virtual_network_access = true
          allow_forwarded_traffic      = true
          allow_gateway_transit        = true
          use_remote_gateways          = false
        } if k_src != k_dst && v_dst.mesh_peering_enabled
      ] if v_src.mesh_peering_enabled
    ]) : peerconfig.name => peerconfig
  }

  resource_group_data = toset([
    for k, v in var.hub_virtual_networks : {
      name      = v.resource_group_name
      location  = v.location
      lock      = v.resource_group_lock_enabled
      lock_name = v.resource_group_lock_name
      tags      = v.resource_group_tags
    } if v.resource_group_creation_enabled
  ])

  route_map = {
    for k_src, v_srv in var.hub_virtual_networks : k_src => flatten([
      for k_dst, v_dst in var.hub_virtual_networks : [
        for cidr in v_dst.routing_address_space : {
          name                   = "${k_dst}-${cidr}"
          address_prefix         = cidr
          next_hop_type          = "VirtualAppliance"
          next_hop_ip_address    = v_dst.hub_router_ip_address # TODO change to support Azure Firewall when module is implemented
        }
      ] if k_src != k_dst && v_dst.mesh_peering_enabled
    ]) if v_src.mesh_peering_enabled
  }
}
