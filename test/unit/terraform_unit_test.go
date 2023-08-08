package unit

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	test_helper "github.com/Azure/terraform-module-test-helper"
	"github.com/ahmetb/go-linq/v3"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/mitchellh/mapstructure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/thanhpk/randstr"
)

type vars map[string]any

func (v vars) toFile(t *testing.T) string {
	return varFile(t, v, fmt.Sprintf("../../unit-fixture/terraform%s.tfvars.json", randstr.Hex(8)))
}

type vnet struct {
	Name                     string            `json:"name"`
	MeshPeeringEnabled       bool              `json:"mesh_peering_enabled"`
	Subnets                  map[string]subnet `json:"subnets"`
	AddressSpace             []string          `json:"address_space"`
	ResourceGroupName        string            `json:"resource_group_name"`
	Location                 string            `json:"location"`
	ResourceGroupLockEnabled bool              `json:"resource_group_lock_enabled"`
	ResourceGroupLockName    string            `json:"resource_group_lock_name"`
	ResourceGroupCreation    bool              `json:"resource_group_creation_enabled"`
	RoutingAddressSpace      []string          `json:"routing_address_space"`
	Firewall                 *firewall         `json:"firewall"`
	HubRouterIpAddress       *string           `json:"hub_router_ip_address"`
	Routes                   []routeEntry      `json:"route_table_entries"`
}

type routeEntry struct {
	Name            string  `json:"name"`
	AddressPrefix   string  `json:"address_prefix"`
	NextHopType     string  `json:"next_hop_type"`
	NextHopIpAddres *string `json:"next_hop_ip_address"`
}

type firewall struct {
	Name                          *string `json:"name"`
	SkuName                       string  `json:"sku_name"`
	SkuTier                       string  `json:"sku_tier"`
	SubnetAddressPrefix           string  `json:"subnet_address_prefix"`
	ManagementSubnetAddressPrefix string  `json:"management_subnet_address_prefix"`
	SubnetRouteTableId            *string `json:"subnet_route_table_id"`
}

type firewallOutputEntry struct {
	Name                          string               `mapstructure:"name"`
	SkuName                       string               `mapstructure:"sku_name"`
	SkuTier                       string               `mapstructure:"sku_tier"`
	SubnetAddressPrefix           string               `mapstructure:"subnet_address_prefix"`
	ManagementSubnetAddressPrefix string               `mapstructure:"management_subnet_address_prefix"`
	SubnetRouteTableId            *string              `mapstructure:"subnet_route_table_id"`
	DnsServers                    []string             `mapstructure:"dns_servers"`
	FirewallPolicyId              *string              `mapstructure:"firewall_policy_id"`
	PrivateIpRanges               []string             `mapstructure:"private_ip_ranges"`
	Tags                          map[string]string    `mapstructure:"tags"`
	ThreatIntelMode               string               `mapstructure:"threat_intel_mode"`
	Zones                         []string             `mapstructure:"zones"`
	DefaultIpConfig               *IpConfigOutputEntry `mapstructure:"default_ip_configuration"`
}

type IpConfigOutputEntry struct {
	Name string `mapstructure:"name"`
}

type subnet struct {
	AddressPrefixes           []string `json:"address_prefixes"`
	AssignGeneratedRouteTable bool     `json:"assign_generated_route_table"`
	ExternalRouteTableId      *string  `json:"external_route_table_id"`
}

func aSubnet(addressSpace string) subnet {
	return subnet{
		AddressPrefixes: []string{addressSpace},
	}
}

func (s subnet) UseGenerateRouteTable() subnet {
	s.AssignGeneratedRouteTable = true
	return s
}

func (s subnet) WithExternalRouteTableId(rtId string) subnet {
	s.ExternalRouteTableId = &rtId
	return s
}

func aVnet(name string, meshPeering bool) vnet {
	return vnet{
		Name:                  name,
		Location:              "eastus",
		MeshPeeringEnabled:    meshPeering,
		Subnets:               make(map[string]subnet, 0),
		ResourceGroupCreation: false,
		HubRouterIpAddress:    String("dummyIp"),
		AddressSpace:          make([]string, 0, 2),
	}
}

func (n vnet) withAddressSpace(cidr string) vnet {
	n.AddressSpace = append(n.AddressSpace, cidr)
	return n
}

func (n vnet) withResourceGroupCreation(b bool) vnet {
	n.ResourceGroupCreation = b
	return n
}

func (n vnet) withResourceGroupName(name string) vnet {
	n.ResourceGroupName = name
	return n
}

func (n vnet) withRoutingAddressSpace(cidr string) vnet {
	n.RoutingAddressSpace = append(n.RoutingAddressSpace, cidr)
	return n
}

func (n vnet) withEmptyRoutingAddressSpace() vnet {
	n.RoutingAddressSpace = []string{}
	return n
}

func (n vnet) withSubnet(name string, s subnet) vnet {
	n.Subnets[name] = s
	return n
}

func (n vnet) withFirewall(f firewall) vnet {
	n.Firewall = &f
	n.HubRouterIpAddress = nil
	return n
}

func (n vnet) withHubRouterIpAddress(ip string) vnet {
	n.HubRouterIpAddress = String(ip)
	return n
}

func (n vnet) withUserRouteEntry(r routeEntry) vnet {
	if n.Routes == nil {
		n.Routes = make([]routeEntry, 0)
	}
	n.Routes = append(n.Routes, r)
	return n
}

type routeMap struct {
	MeshRoutes []routeEntryOutput `mapstructure:"mesh_routes"`
	UserRoutes []routeEntryOutput `mapstructure:"user_routes"`
}

type routeEntryOutput struct {
	Name             string  `mapstructure:"name"`
	AddressPrefix    string  `mapstructure:"address_prefix"`
	NextHopType      string  `mapstructure:"next_hop_type"`
	NextHopIpAddress *string `mapstructure:"next_hop_ip_address"`
}

func TestUnit_VnetWithMeshPeeringShouldAppearInHubPeeringMap(t *testing.T) {
	inputs := []struct {
		vars                 vars
		expectedPeeringCount int
	}{
		{
			vars: vars{
				"hub_virtual_networks": map[string]vnet{
					"vnet0":       aVnet("vnet-zero", true).withAddressSpace("10.0.0.0/16"),
					"vnet1":       aVnet("vnet-one", true).withAddressSpace("10.1.0.0/16"),
					"nonMeshVnet": aVnet("nonMeshVnet", false).withAddressSpace("10.2.0.0/16"),
				},
			},
			expectedPeeringCount: 2,
		},
		{
			vars: vars{
				"hub_virtual_networks": map[string]vnet{
					"vnet0":       aVnet("vnet0", true).withAddressSpace("10.0.0.0/16"),
					"vnet1":       aVnet("vnet1", true).withAddressSpace("10.1.0.0/16"),
					"vnet2":       aVnet("vnet2", true).withAddressSpace("10.2.0.0/16"),
					"nonMeshVnet": aVnet("nonMeshVnet", false).withAddressSpace("10.3.0.0/16"),
				},
			},
			expectedPeeringCount: 6,
		},
	}

	for _, input := range inputs {
		i := input
		t.Run(strconv.Itoa(i.expectedPeeringCount), func(t *testing.T) {
			varFilePath := i.vars.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				peeringMap := output["hub_peering_map"].(map[string]any)
				assert.Equal(t, i.expectedPeeringCount, len(peeringMap))
				for k, v := range peeringMap {
					m := v.(map[string]any)
					srcVnetName := i.vars["hub_virtual_networks"].(map[string]vnet)[m["src_key"].(string)].Name
					dstVnetName := i.vars["hub_virtual_networks"].(map[string]vnet)[m["dst_key"].(string)].Name
					expectedPeeringName := fmt.Sprintf("%s-%s", srcVnetName, dstVnetName)
					assert.Equal(t, expectedPeeringName, k)
					assert.Equal(t, srcVnetName, m["virtual_network_name"])
					assert.Equal(t, fmt.Sprintf("%s_id", dstVnetName), m["remote_virtual_network_id"])
					assert.False(t, strings.Contains(k, "nonMeshVnet"))
				}
			})
		})
	}
}

func TestUnit_VnetWithResourceGroupCreationWouldBeGatheredInResourceGroupData(t *testing.T) {
	varFilePath := vars{
		"hub_virtual_networks": map[string]vnet{
			"vnet0": aVnet("vnet0", true).withResourceGroupName("newRg").withResourceGroupCreation(true).withAddressSpace("10.0.0.0/16"),
			"vnet1": aVnet("vnet1", true).withResourceGroupName("existedRg").withResourceGroupCreation(false).withAddressSpace("10.1.0.0/16"),
		},
	}.toFile(t)
	defer func() { _ = os.Remove(varFilePath) }()
	test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
		Upgrade:  true,
		VarFiles: []string{varFilePath},
		Logger:   logger.Discard,
	}, func(t *testing.T, output test_helper.TerraformOutput) {
		data, ok := output["resource_group_data"].([]any)
		require.True(t, ok)
		assert.Len(t, data, 1)
		assert.Equal(t, "newRg", data[0].(map[string]any)["name"])
	})
}

func TestUnit_VnetWithRoutingAddressSpaceWouldProvisionRouteEntries(t *testing.T) {
	inputs := []struct {
		name     string
		networks map[string]vnet
		expected map[string][]routeEntryOutput
	}{
		{
			name: "null routing address should create empty route table",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).withAddressSpace("10.0.0.0/16"),
				"vnet1": aVnet("vnet1", true).withAddressSpace("10.1.0.0/16"),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {},
				"vnet1": {},
			},
		},
		{
			name: "empty routing address should create empty route table",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).withEmptyRoutingAddressSpace().withAddressSpace("10.0.0.0/16"),
				"vnet1": aVnet("vnet1", true).withEmptyRoutingAddressSpace().withAddressSpace("10.1.0.0/16"),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {},
				"vnet1": {},
			},
		},
		{
			name: "uni-directional route",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).withAddressSpace("10.0.0.0/16"),
				"vnet1": aVnet("vnet1", true).withAddressSpace("10.1.0.0/16").withRoutingAddressSpace("10.0.0.0/16"),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {
					{
						Name:             "vnet1-10.0.0.0-16",
						AddressPrefix:    "10.0.0.0/16",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("dummyIp"),
					},
				},
				"vnet1": {},
			},
		},
		{
			name: "bi-directional route",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).
					withAddressSpace("10.0.0.0/16").
					withRoutingAddressSpace("10.0.0.0/16").
					withFirewall(firewall{
						SkuName:             "AZFW_VNet",
						SkuTier:             "Standard",
						SubnetAddressPrefix: "10.0.1.0/24",
					}).
					withSubnet("AzureFirewallSubnet", subnet{
						AddressPrefixes: []string{"10.0.255.0/24"},
					}),
				"vnet1": aVnet("vnet1", true).
					withAddressSpace("10.1.0.0/16").
					withRoutingAddressSpace("10.1.0.0/16").
					withFirewall(firewall{
						SkuName:             "AZFW_VNet",
						SkuTier:             "Standard",
						SubnetAddressPrefix: "10.1.1.0/24",
					}).
					withSubnet("AzureFirewallSubnet", subnet{
						AddressPrefixes: []string{"10.0.255.0/24"},
					}),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {
					{
						Name:             "vnet1-10.1.0.0-16",
						AddressPrefix:    "10.1.0.0/16",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("vnet1-fake-fw-private-ip"),
					},
				},
				"vnet1": {
					{
						Name:             "vnet0-10.0.0.0-16",
						AddressPrefix:    "10.0.0.0/16",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("vnet0-fake-fw-private-ip"),
					},
				},
			},
		},
	}

	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			varFilePath := vars{
				"hub_virtual_networks": input.networks,
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				var actual map[string]routeMap
				err := mapstructure.Decode(output["route_map"], &actual)
				require.NoError(t, err)
				require.Equal(t, len(input.expected), len(actual))
				for vnetName, a := range actual {
					meshRoutes := sortRouteEntryOutputs(a.MeshRoutes)
					expected := sortRouteEntryOutputs(input.expected[vnetName])
					assert.Equal(t, expected, meshRoutes)
				}
			})
		})
	}
}

func TestUnit_VnetWithUserRouteEntriesWouldProvisionUserRouteEntries(t *testing.T) {
	inputs := []struct {
		name     string
		networks map[string]vnet
		expected map[string][]routeEntryOutput
	}{
		{
			name: "null routing address should create empty route table",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).
					withAddressSpace("10.0.0.0/16").
					withUserRouteEntry(routeEntry{
						Name:          "no_internet",
						AddressPrefix: "0.0.0.0/0",
						NextHopType:   "None",
					}).withUserRouteEntry(routeEntry{
					Name:          "intranet",
					AddressPrefix: "10.0.0.0/16",
					NextHopType:   "VnetLocal",
				}),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {
					routeEntryOutput{
						Name:          "intranet",
						AddressPrefix: "10.0.0.0/16",
						NextHopType:   "VnetLocal",
					},
					routeEntryOutput{
						Name:          "no_internet",
						AddressPrefix: "0.0.0.0/0",
						NextHopType:   "None",
					},
				},
			},
		},
		{
			name: "bi-directional route",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).
					withAddressSpace("10.0.0.0/16").
					withRoutingAddressSpace("10.0.0.0/16").
					withFirewall(firewall{
						SkuName:             "AZFW_VNet",
						SkuTier:             "Standard",
						SubnetAddressPrefix: "10.0.0.0/24",
					}).
					withSubnet("AzureFirewallSubnet", subnet{
						AddressPrefixes: []string{"10.0.255.0/24"},
					}).withUserRouteEntry(routeEntry{
					Name:          "no_internet",
					AddressPrefix: "0.0.0.0/0",
					NextHopType:   "None",
				}).withUserRouteEntry(routeEntry{
					Name:          "intranet",
					AddressPrefix: "10.0.0.0/16",
					NextHopType:   "VnetLocal",
				}),
				"vnet1": aVnet("vnet1", true).
					withAddressSpace("10.1.0.0/16").
					withRoutingAddressSpace("10.1.0.0/16").
					withFirewall(firewall{
						SkuName:             "AZFW_VNet",
						SkuTier:             "Standard",
						SubnetAddressPrefix: "10.1.0.0/24",
					}).
					withSubnet("AzureFirewallSubnet", subnet{
						AddressPrefixes: []string{"10.0.255.0/24"},
					}),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {
					{
						Name:          "intranet",
						AddressPrefix: "10.0.0.0/16",
						NextHopType:   "VnetLocal",
					},
					{
						Name:          "no_internet",
						AddressPrefix: "0.0.0.0/0",
						NextHopType:   "None",
					},
				},
				"vnet1": nil,
			},
		},
	}

	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			varFilePath := vars{
				"hub_virtual_networks": input.networks,
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				var actual map[string]routeMap
				err := mapstructure.Decode(output["route_map"], &actual)
				require.NoError(t, err)
				require.Equal(t, len(input.expected), len(actual))
				for vnetName, a := range actual {
					userRoutes := sortRouteEntryOutputs(a.UserRoutes)
					expected := sortRouteEntryOutputs(input.expected[vnetName])
					assert.Equal(t, expected, userRoutes)
				}
			})
		})
	}
}

func TestUnit_SubnetAssignGeneratedRouteTableWouldProvisionGeneratedRouteTableAssociation(t *testing.T) {
	inputs := []struct {
		name     string
		network  vnet
		expected map[string]any
	}{
		{
			name: "no association to generated route table",
			network: aVnet("vnet0", false).
				withAddressSpace("10.0.0.0/16").
				withSubnet("subnet0", aSubnet("10.0.0.0/24")),
			expected: map[string]any{},
		},
		{
			name: "association to generated route table",
			network: aVnet("vnet0", false).
				withAddressSpace("10.0.0.0/16").
				withSubnet("subnetAssociatedWithGeneratedRouteTable", aSubnet("10.0.0.0/24").UseGenerateRouteTable()).
				withSubnet("subnetAssociatedWithExternalRouteTable", aSubnet("10.0.1.0/24").WithExternalRouteTableId("external_route_table_id")),
			expected: map[string]any{
				"vnet0-subnetAssociatedWithGeneratedRouteTable": map[string]any{
					"name":           "vnet0-subnetAssociatedWithGeneratedRouteTable",
					"subnet_id":      "subnetAssociatedWithGeneratedRouteTable_id",
					"route_table_id": "vnet0_route_table_id",
				},
			},
		},
	}
	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			varFilePath := vars{
				"hub_virtual_networks": map[string]any{
					input.network.Name: input.network,
				},
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				subnetGenerateRouteTableAssociatoins := output["subnet_route_table_association_map"].(map[string]any)
				assert.Equal(t, input.expected, subnetGenerateRouteTableAssociatoins)
			})
		})
	}
}

func TestUnit_SubnetAssignExternalRouteTableWouldProvisionAssociationToExternalRouteTable(t *testing.T) {
	inputs := []struct {
		name     string
		network  vnet
		expected map[string]any
	}{
		{
			name: "no association to external route table",
			network: aVnet("vnet0", false).
				withAddressSpace("10.0.0.0/16").
				withAddressSpace("10.0.0.0/16").
				withSubnet("subnet0", aSubnet("10.0.0.0/24")),
			expected: map[string]any{},
		},
		{
			name: "association to external route table",
			network: aVnet("vnet0", false).
				withAddressSpace("10.0.0.0/16").
				withSubnet("subnetAssociatedWithGeneratedRouteTable", aSubnet("10.0.0.0/24").UseGenerateRouteTable()).
				withSubnet("subnetAssociatedWithExternalRouteTable", aSubnet("10.0.1.0/24").WithExternalRouteTableId("external_route_table_id")),
			expected: map[string]any{
				"vnet0-subnetAssociatedWithExternalRouteTable": map[string]any{
					"name":           "vnet0-subnetAssociatedWithExternalRouteTable",
					"subnet_id":      "subnetAssociatedWithExternalRouteTable_id",
					"route_table_id": "external_route_table_id",
				},
			},
		},
	}
	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			varFilePath := vars{
				"hub_virtual_networks": map[string]any{
					input.network.Name: input.network,
				},
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				externalRouteTableAssociations := output["subnet_external_route_table_association_map"].(map[string]any)
				assert.Equal(t, input.expected, externalRouteTableAssociations)
			})
		})
	}
}

func TestUnit_VnetWithFirewallShouldCreatePublicIp(t *testing.T) {
	inputs := []struct {
		name     string
		network  vnet
		expected map[string]any
	}{
		{
			name: "vnet without firewall should not create public ip",
			network: aVnet("vnet", false).
				withResourceGroupName("rg0").
				withAddressSpace("10.0.0.0/16").
				withSubnet("AzureFirewallSubnet", subnet{
					AddressPrefixes:           []string{"10.0.255.0/24"},
					AssignGeneratedRouteTable: false,
					ExternalRouteTableId:      nil,
				}),
			expected: map[string]any{},
		},
		{
			name: "vnet firewall should create public ip",
			network: aVnet("vnet", false).
				withResourceGroupName("rg0").
				withAddressSpace("10.0.0.0/16").
				withFirewall(firewall{
					SkuName:                       "AZFW_VNet",
					SkuTier:                       "Basic",
					SubnetAddressPrefix:           "10.0.255.0/24",
					ManagementSubnetAddressPrefix: "10.0.1.0/24",
				}),
			expected: map[string]any{
				"vnet": map[string]any{
					"location":            "eastus",
					"name":                "pip-afw-vnet",
					"resource_group_name": "rg0",
					"ip_version":          "IPv4",
					"sku_tier":            "Regional",
					"zones":               nil,
				},
			},
		},
	}

	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			varFilePath := vars{
				"hub_virtual_networks": map[string]any{
					input.network.Name: input.network,
				},
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				pips := output["fw_default_ip_configuration_pip"]
				assert.Equal(t, input.expected, pips)
			})
		})
	}
}

func TestUnit_VnetWithFirewallShouldCreateFirewall(t *testing.T) {
	inputs := []struct {
		name     string
		network  vnet
		expected map[string]firewallOutputEntry
	}{
		{
			name: "vnet without firewall should not create firewall",
			network: aVnet("vnet", false).
				withResourceGroupName("rg0").
				withAddressSpace("10.0.0.0/16"),
			expected: map[string]firewallOutputEntry{},
		},
		{
			name: "vnet firewall should create firewall",
			network: aVnet("vnet", false).
				withResourceGroupName("rg0").
				withAddressSpace("10.0.0.0/16").
				withFirewall(firewall{
					SkuName:             "AZFW_VNet",
					SkuTier:             "Standard",
					SubnetAddressPrefix: "10.0.255.0/24",
				}),
			expected: map[string]firewallOutputEntry{
				"vnet": {
					Name:                "afw-vnet",
					SkuName:             "AZFW_VNet",
					SkuTier:             "Standard",
					SubnetAddressPrefix: "10.0.255.0/24",
					ThreatIntelMode:     "Alert",
					DefaultIpConfig: &IpConfigOutputEntry{
						Name: "default",
					},
				},
			},
		},
	}

	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			varFilePath := vars{
				"hub_virtual_networks": map[string]any{
					input.network.Name: input.network,
				},
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				actual := make(map[string]firewallOutputEntry, 0)
				err := mapstructure.Decode(output["firewalls"], &actual)
				require.NoError(t, err)
				assert.Equal(t, input.expected, actual)
			})
		})
	}
}

func TestUnit_RoutingAddressSpaceShouldGenerateMeshRoutes(t *testing.T) {
	inputs := []struct {
		name     string
		network  []vnet
		expected map[string][]routeEntryOutput
	}{
		{
			name: "vnet without firewall should not create firewall",
			network: []vnet{
				aVnet("vnet0", true).
					withAddressSpace("10.0.0.0/16").
					withRoutingAddressSpace("10.0.0.0/16").
					withRoutingAddressSpace("192.168.0.0/24").
					withHubRouterIpAddress("fake_fw_vnet0_ip"),
				aVnet("vnet1", true).
					withAddressSpace("10.1.0.0/16").
					withRoutingAddressSpace("10.1.0.0/16").
					withRoutingAddressSpace("192.168.1.0/24").
					withHubRouterIpAddress("fake_fw_vnet1_ip"),
			},
			expected: map[string][]routeEntryOutput{
				"vnet0": {
					{
						Name:             "vnet1-10.1.0.0-16",
						AddressPrefix:    "10.1.0.0/16",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("fake_fw_vnet1_ip"),
					},
					{
						Name:             "vnet1-192.168.1.0-24",
						AddressPrefix:    "192.168.1.0/24",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("fake_fw_vnet1_ip"),
					},
				},
				"vnet1": {
					{
						Name:             "vnet0-10.0.0.0-16",
						AddressPrefix:    "10.0.0.0/16",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("fake_fw_vnet0_ip"),
					},
					{
						Name:             "vnet0-192.168.0.0-24",
						AddressPrefix:    "192.168.0.0/24",
						NextHopType:      "VirtualAppliance",
						NextHopIpAddress: String("fake_fw_vnet0_ip"),
					},
				},
			},
		},
	}

	for i := 0; i < len(inputs); i++ {
		input := inputs[i]
		t.Run(input.name, func(t *testing.T) {
			networks := make(map[string]any)
			linq.From(input.network).ToMapBy(&networks, func(i interface{}) interface{} {
				return i.(vnet).Name
			}, func(i interface{}) interface{} {
				return i
			})
			varFilePath := vars{
				"hub_virtual_networks": networks,
			}.toFile(t)
			defer func() { _ = os.Remove(varFilePath) }()
			test_helper.RunUnitTest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				var actual map[string]routeMap
				err := mapstructure.Decode(output["route_map"], &actual)
				require.NoError(t, err)
				require.Equal(t, len(input.expected), len(actual))
				for vnetName, a := range actual {
					meshRoutes := sortRouteEntryOutputs(a.MeshRoutes)
					expected := sortRouteEntryOutputs(input.expected[vnetName])
					assert.Equal(t, expected, meshRoutes)
				}
			})
		})
	}
}

func varFile(t *testing.T, inputs map[string]interface{}, path string) string {
	cleanPath := filepath.Clean(path)
	varFile, err := os.Create(cleanPath)
	require.Nil(t, err)
	c, err := json.Marshal(inputs)
	require.Nil(t, err)
	_, err = varFile.Write(c)
	require.Nil(t, err)
	_ = varFile.Close()
	varFilePath, err := filepath.Abs(cleanPath)
	require.Nil(t, err)
	return varFilePath
}

func String(s string) *string {
	return &s
}

func sortRouteEntryOutputs(routes []routeEntryOutput) []routeEntryOutput {
	var r []routeEntryOutput
	linq.From(routes).Sort(func(i, j interface{}) bool {
		return strings.Compare(i.(routeEntryOutput).Name, j.(routeEntryOutput).Name) < 0
	}).ToSlice(&r)
	return r
}
