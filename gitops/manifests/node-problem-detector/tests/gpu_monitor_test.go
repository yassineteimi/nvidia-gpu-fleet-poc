// Tests for gpu-monitor.json, run inside node-problem-detector's own
// systemlogmonitor package at the version the cluster deploys, so the rules go
// through the real buffer, the real "match to the end" regexp and the real
// condition logic. scripts/test-npd-rules.sh copies this file into a checkout
// of node-problem-detector and runs it; it is not part of any Go module here.

package systemlogmonitor

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	systemlogtypes "k8s.io/node-problem-detector/pkg/systemlogmonitor/types"
	"k8s.io/node-problem-detector/pkg/types"
)

// The device plugin's application errors (internal/rm/health.go, v0.20.0).
var applicationXids = map[int]bool{13: true, 31: true, 43: true, 45: true, 68: true, 109: true}

func loadGPUMonitor(t *testing.T) *logMonitor {
	t.Helper()
	raw, err := os.ReadFile(os.Getenv("GPU_MONITOR_CONFIG"))
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	var cfg MonitorConfig
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Fatalf("parse config: %v", err)
	}
	cfg.ApplyDefaultConfiguration()
	if err := cfg.ValidateRules(); err != nil {
		t.Fatalf("invalid rule: %v", err)
	}
	off := false
	cfg.EnableMetricsReporting = &off // no metrics manager in a unit test
	return &logMonitor{
		config:     cfg,
		buffer:     NewLogBuffer(cfg.BufferSize),
		output:     make(chan *types.Status, 64),
		conditions: initialConditions(cfg.DefaultConditions),
	}
}

// feed pushes one kernel log line and returns every status the rules produced.
func feed(l *logMonitor, line string) []*types.Status {
	l.parseLog(&systemlogtypes.Log{Timestamp: time.Now(), Message: strings.TrimSpace(line)})
	var out []*types.Status
	for {
		select {
		case s := <-l.output:
			out = append(out, s)
		default:
			return out
		}
	}
}

func condition(l *logMonitor) types.Condition {
	for _, c := range l.conditions {
		if c.Type == "GPUUnhealthy" {
			return c
		}
	}
	panic("no GPUUnhealthy condition")
}

func eventReasons(statuses []*types.Status) []string {
	var reasons []string
	for _, s := range statuses {
		for _, e := range s.Events {
			reasons = append(reasons, e.Reason)
		}
	}
	return reasons
}

func xidLine(code int) string {
	return fmt.Sprintf("NVRM: Xid (PCI:0000:01:00): %d, pid=4242, name=python3, test message", code)
}

// Every code from 0 to 2000: the condition is set exactly for the codes the
// device plugin treats as GPU faults, and every code produces a GPUXid event.
func TestEveryXidIsClassifiedLikeTheDevicePlugin(t *testing.T) {
	for code := 0; code <= 2000; code++ {
		l := loadGPUMonitor(t)
		statuses := feed(l, xidLine(code))
		c := condition(l)
		wantFault := !applicationXids[code]
		if (c.Status == types.True) != wantFault {
			t.Errorf("XID %d: GPUUnhealthy=%s, want fault=%v", code, c.Status, wantFault)
		}
		if wantFault && c.Reason != "GPUXidFault" {
			t.Errorf("XID %d: reason %q", code, c.Reason)
		}
		if !strings.Contains(strings.Join(eventReasons(statuses), ","), "GPUXid") {
			t.Errorf("XID %d: no GPUXid event", code)
		}
	}
}

// The three shapes of the format string in kernel_rc.c at driver 595.91.07,
// including the bare "%d, " that TrimSpace turns into "79,".
func TestEveryShapeTheDriverPrints(t *testing.T) {
	for _, line := range []string{
		"NVRM: Xid (PCI:0000:01:00): 79, pid=1234, name=python3, GPU has fallen off the bus.",
		"NVRM: Xid (PCI:0000:01:00): 79, GPU has fallen off the bus.",
		"NVRM: Xid (PCI:0000:01:00): 79, ",
		"NVRM: Xid (PCI:0000:3b:00 GPU-I:01 GPU-CI:02): 79, pid=9, name=a, GPU has fallen off the bus.",
		"NVRM: Xid (PCI:0000:3b:00 GPU-I:01): 79, GPU has fallen off the bus.",
	} {
		l := loadGPUMonitor(t)
		feed(l, line)
		if condition(l).Status != types.True {
			t.Errorf("not matched: %q", line)
		}
	}
}

func TestOtherKernelLinesAreIgnored(t *testing.T) {
	l := loadGPUMonitor(t)
	for _, line := range []string{
		"NVRM: GPU at PCI:0000:01:00: GPU-1e61ad7a-9486-bed3-4cb3-065b17451322",
		"NVRM: loading NVIDIA UNIX Open Kernel Module for x86_64  595.91.07",
		"nouveau 0000:01:00.0: Xid 79",
		"Xid (PCI:0000:01:00): 79, not from NVRM",
	} {
		if s := feed(l, line); len(s) != 0 {
			t.Errorf("line produced a status: %q", line)
		}
	}
	if condition(l).Status != types.False {
		t.Error("condition set by a non-Xid line")
	}
}

// An application XID first must not hide a fault XID that follows it.
func TestFaultAfterApplicationErrorStillSetsTheCondition(t *testing.T) {
	l := loadGPUMonitor(t)
	feed(l, xidLine(13))
	if condition(l).Status != types.False {
		t.Fatal("XID 13 set the condition")
	}
	feed(l, xidLine(79))
	c := condition(l)
	if c.Status != types.True || !strings.Contains(c.Message, "): 79,") {
		t.Errorf("after 13 then 79: status %s, message %q", c.Status, c.Message)
	}
}

// Documents node-problem-detector's behaviour rather than ours: once the
// condition is True with the same reason, later lines don't change its message.
// The controller acts on the first fault, which is the one that matters.
func TestConditionMessageKeepsTheFirstFault(t *testing.T) {
	l := loadGPUMonitor(t)
	feed(l, xidLine(79))
	feed(l, xidLine(48))
	if msg := condition(l).Message; !strings.Contains(msg, "): 79,") {
		t.Errorf("message changed to %q", msg)
	}
}
