locals {
  hub_peering = {
    for p in [
      for peer in flatten([
        for k_src, v_src in var.hub_virtual_networks :
        [
          for k_dst, v_dst in var.hub_virtual_networks :
          {
            src_virtual_network_name = v_src.name
            dst_virtual_network_name = v_dst.name
          } if k_src != k_dst && v_dst.mesh_peering_enabled
        ] if v_src.mesh_peering_enabled
      ]) : peer
    ] : p.src_virtual_network_name => p.dst_virtual_network_name...
  }
  # Logic to determine the number of peerings to create for all hub networks with mesh_peering enabled.
  middle = { for peering in flatten([
    for src_vnet_name, dest_vnet_names in local.hub_peering : [
      for dest_vnet_name in dest_vnet_names : {
        name                         = "${src_vnet_name}-${dest_vnet_name}"
        virtual_network_name         = src_vnet_name
        remote_virtual_network_id    = local.virtual_networks_modules[dest_vnet_name].vnet_id
        allow_virtual_network_access = true
        allow_forwarded_traffic      = true
        allow_gateway_transit        = true
        use_remote_gateways          = false
      }
    ]
  ]) : peering.name => peering}

  hub_peering_map = {
    for peerconfig in flatten([
      for k_src, v_src in var.hub_virtual_networks :
      [
        for k_dst, v_dst in var.hub_virtual_networks :
        {
          name                         = "${k_src}-${k_dst}"
          virtual_network_name         = local.virtual_networks_modules[k_src].vnet_name
          remote_virtual_network_id    = local.virtual_networks_modules[k_dst].vnet_id
          allow_virtual_network_access = true
          allow_forwarded_traffic      = true
          allow_gateway_transit        = true
          use_remote_gateways          = false
        } if k_src != k_dst && v_dst.mesh_peering_enabled
      ] if v_src.mesh_peering_enabled
    ]) : peerconfig.name => peerconfig
  }
  # Create a unique set of resource groups to create
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
    for k_src, v_src in var.hub_virtual_networks : k_src => flatten([
      for k_dst, v_dst in var.hub_virtual_networks : [
        for cidr in v_dst.routing_address_space : {
          name                = "${k_dst}-${cidr}"
          address_prefix      = cidr
          next_hop_type       = "VirtualAppliance"
          next_hop_ip_address = v_dst.hub_router_ip_address
          # TODO change to support Azure Firewall when module is implemented
        }
      ] if k_src != k_dst && v_dst.mesh_peering_enabled && length(v_dst.routing_address_space) != 0
    ]) if v_src.mesh_peering_enabled
  }
  subnet_external_route_table_association_map = {
    for assoc in flatten([
      for k, v in var.hub_virtual_networks : [
        for subnet in v.subnets : {
          name           = "${k}-${subnet.name}"
          subnet_id      = lookup(local.virtual_networks_modules[k].vnet_subnets_name_id, subnet.name)
          route_table_id = subnet.external_route_table_id
        } if subnet.external_route_table_id != null
      ]
    ]) : assoc.name => assoc
  }

  subnets_map = {
    for k, v in var.hub_virtual_networks : k => {
      for subnetKey, subnet in v.subnets : subnetKey => {
        address_prefixes                              = subnet.address_prefixes
        nat_gateway                                   = subnet.nat_gateway
        network_security_group                        = subnet.network_security_group
        private_endpoint_network_policies_enabled     = subnet.private_endpoint_network_policies_enabled
        private_link_service_network_policies_enabled = subnet.private_link_service_network_policies_enabled
        service_endpoints                             = subnet.service_endpoints
        service_endpoint_policy_ids                   = subnet.service_endpoint_policy_ids
        delegations                                   = subnet.delegations
      }
    }
  }
}
