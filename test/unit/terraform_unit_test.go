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
}

type subnet struct {
	AddressPrefixes []string `json:"address_prefixes"`
}

func aVnet(name string, meshPeering bool) vnet {
	return vnet{
		Name:                  name,
		MeshPeeringEnabled:    meshPeering,
		Subnets:               make(map[string]subnet, 0),
		ResourceGroupCreation: true,
	}
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
	n.AddressSpace = []string{}
	return n
}

func (n vnet) withSubnet(name, addressSpace string) vnet {
	n.Subnets[name] = subnet{AddressPrefixes: []string{addressSpace}}
	return n
}

type routeEntry struct {
	Name             string `mapstructure:"name"`
	AddressPrefix    string `mapstructure:"address_prefix"`
	NextHopIpAddress string `mapstructure:"next_hop_ip_address"`
}

func TestUnit_VnetWithMeshPeeringShouldAppearInHubPeeringMap(t *testing.T) {
	inputs := []struct {
		vars                 vars
		expectedPeeringCount int
	}{
		{
			vars: vars{
				"hub_virtual_networks": map[string]vnet{
					"vnet0":       aVnet("vnet0", true),
					"vnet1":       aVnet("vnet1", true),
					"nonMeshVnet": aVnet("nonMeshVnet", false),
				},
			},
			expectedPeeringCount: 2,
		},
		{
			vars: vars{
				"hub_virtual_networks": map[string]vnet{
					"vnet0":       aVnet("vnet0", true),
					"vnet1":       aVnet("vnet1", true),
					"vnet2":       aVnet("vnet2", true),
					"nonMeshVnet": aVnet("nonMeshVnet", false),
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
			test_helper.RunE2ETest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				peeringMap := output["hub_peering_map"].(map[string]any)
				assert.Equal(t, i.expectedPeeringCount, len(peeringMap))
				for k, v := range peeringMap {
					assert.Regexp(t, `vnet\d-vnet\d`, k)
					split := strings.Split(k, "-")
					srcVnetName := split[0]
					dstVnetName := split[1]
					m := v.(map[string]any)
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
			"vnet0": aVnet("vnet0", true).withResourceGroupName("newRg").withResourceGroupCreation(true),
			"vnet1": aVnet("vnet1", true).withResourceGroupName("existedRg").withResourceGroupCreation(false),
		},
	}.toFile(t)
	defer func() { _ = os.Remove(varFilePath) }()
	test_helper.RunE2ETest(t, "../../", "unit-fixture", terraform.Options{
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
		expected map[string][]routeEntry
	}{
		{
			name: "null routing address should create empty route table",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true),
				"vnet1": aVnet("vnet1", true),
			},
			expected: map[string][]routeEntry{
				"vnet0": {},
				"vnet1": {},
			},
		},
		{
			name: "empty routing address should create empty route table",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).withEmptyRoutingAddressSpace(),
				"vnet1": aVnet("vnet1", true).withEmptyRoutingAddressSpace(),
			},
			expected: map[string][]routeEntry{
				"vnet0": {},
				"vnet1": {},
			},
		},
		{
			name: "uni-directional route",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true),
				"vnet1": aVnet("vnet1", true).withRoutingAddressSpace("10.0.0.0/16"),
			},
			expected: map[string][]routeEntry{
				"vnet0": {
					{
						Name:          "vnet1-10.0.0.0/16",
						AddressPrefix: "10.0.0.0/16",
					},
				},
				"vnet1": {},
			},
		},
		{
			name: "bi-directional route",
			networks: map[string]vnet{
				"vnet0": aVnet("vnet0", true).withRoutingAddressSpace("10.0.0.0/16"),
				"vnet1": aVnet("vnet1", true).withRoutingAddressSpace("10.1.0.0/16"),
			},
			expected: map[string][]routeEntry{
				"vnet0": {
					{
						Name:          "vnet1-10.1.0.0/16",
						AddressPrefix: "10.1.0.0/16",
					},
				},
				"vnet1": {
					{
						Name:          "vnet0-10.0.0.0/16",
						AddressPrefix: "10.0.0.0/16",
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
			test_helper.RunE2ETest(t, "../../", "unit-fixture", terraform.Options{
				Upgrade:  true,
				VarFiles: []string{varFilePath},
				Logger:   logger.Discard,
			}, func(t *testing.T, output test_helper.TerraformOutput) {
				var actual map[string][]routeEntry
				err := mapstructure.Decode(output["route_map"], &actual)
				require.Nil(t, err)
				assert.Equal(t, input.expected, actual)
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
