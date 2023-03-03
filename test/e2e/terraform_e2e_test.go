package e2e

import (
	"bytes"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/retry"

	test_helper "github.com/Azure/terraform-module-test-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestExmaples_startup(t *testing.T) {
	test_helper.RunE2ETest(t, "../../", "examples/startup", terraform.Options{
		Upgrade: true,
	}, func(t *testing.T, output test_helper.TerraformOutput) {
		testUrl := output["connectivity_test_url"].(string)
		response := retry.DoWithRetry(t, "assert_network_connectivity", 5, time.Minute, func() (string, error) {
			resp, err := http.Get(testUrl)
			if err != nil {
				return "", err
			}
			defer resp.Body.Close()
			buf := new(bytes.Buffer)
			_, err = buf.ReadFrom(resp.Body)
			if err != nil {
				return "", err
			}
			return buf.String(), nil
		})
		response = strings.TrimSuffix(response, "\n")
		assert.Equal(t, "hello world", response)
	})
}
