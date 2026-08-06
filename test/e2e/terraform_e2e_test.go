package e2e

import (
	"net"
	"testing"

	test_helper "github.com/Azure/terraform-module-test-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestExmaples_startup(t *testing.T) {
	test_helper.RunE2ETest(t, "../../", "examples/startup", terraform.Options{
		Upgrade: true,
	}, func(t *testing.T, output test_helper.TerraformOutput) {
		pip := output["spoke2_pip"].(string)
		assert.NotNil(t, net.ParseIP(pip))
	})
}

func TestExmaples_fw_multiple_public_ip(t *testing.T) {
	test_helper.RunE2ETest(t, "../../", "examples/fw_multiple_public_ips", terraform.Options{
		Upgrade: true,
	}, nil)
}
