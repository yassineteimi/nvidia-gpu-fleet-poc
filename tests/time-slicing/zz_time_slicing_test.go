// Parses the ts-4 config from gitops/values/gpu-operator-time-slicing.yaml
// with the NVIDIA device plugin's own config loader at v0.20.0.
// scripts/test-time-slicing.sh copies this file into api/config/v1 of that
// checkout and passes the extracted config through TS_CONFIG.
package v1

import (
	"os"
	"strings"
	"testing"
)

func TestTimeSlicingConfigParses(t *testing.T) {
	raw := os.Getenv("TS_CONFIG")
	if raw == "" {
		t.Fatal("TS_CONFIG is empty")
	}
	cfg, err := parseConfigFrom(strings.NewReader(raw))
	if err != nil {
		t.Fatalf("device plugin rejected the config: %v", err)
	}
	rs := cfg.Sharing.TimeSlicing.Resources
	if len(rs) != 1 || rs[0].Name != "nvidia.com/gpu" || rs[0].Replicas != 4 {
		t.Fatalf("unexpected time slicing resources: %+v", rs)
	}
	if !cfg.Sharing.TimeSlicing.isReplicated() {
		t.Fatal("config is not treated as replicated")
	}
	if cfg.Sharing.TimeSlicing.RenameByDefault {
		t.Fatal("renameByDefault would advertise nvidia.com/gpu.shared, and the quotas count nvidia.com/gpu")
	}
}
