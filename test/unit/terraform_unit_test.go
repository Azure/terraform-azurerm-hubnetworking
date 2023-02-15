package unit

import (
	"fmt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/thanhpk/randstr"
	"k8s.io/apimachinery/pkg/util/json"
	"os"
	"path/filepath"
	"testing"

	test_helper "github.com/Azure/terraform-module-test-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
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

func (n vnet) withSubnet(name, addressSpace string) vnet {
	n.Subnets[name] = subnet{AddressPrefixes: []string{addressSpace}}
	return n
}

func TestUnit_VnetWithMeshPeeringShouldAppearInHubPeeringMap(t *testing.T) {
	varFilePath := vars{
		"hub_virtual_networks": map[string]vnet{
			"vnet0":       aVnet("vnet0", true),
			"vnet1":       aVnet("vnet1", true),
			"nonMeshVnet": aVnet("nonMeshVnet", false),
		},
	}.toFile(t)
	defer func() { _ = os.Remove(varFilePath) }()
	test_helper.RunE2ETest(t, "../../", "unit-fixture", terraform.Options{
		Upgrade:  true,
		VarFiles: []string{varFilePath},
	}, func(t *testing.T, output test_helper.TerraformOutput) {
		peeringMap := output["hub_peering_map"].(map[string]any)
		assert.Equal(t, 2, len(peeringMap))
	})
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
	}, func(t *testing.T, output test_helper.TerraformOutput) {
		data, ok := output["resource_group_data"].([]any)
		require.True(t, ok)
		assert.Len(t, data, 1)
		assert.Equal(t, "newRg", data[0].(map[string]any)["name"])
	})
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
