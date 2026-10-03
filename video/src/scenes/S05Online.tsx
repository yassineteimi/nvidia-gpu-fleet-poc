import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { C } from "../theme";
import { Kicker, Rise, Scene, Sub } from "../ui";

// The driver is a line in Git; the GPU Operator installs it on a node that booted with none.
export const S05Online: React.FC = () => {
  const f = useCurrentFrame();
  const line = 'version: "595.91.07"';
  const typed = line.slice(0, Math.max(0, Math.floor((f - 15) / 1.6)));
  const dot = interpolate(f, [55, 85], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const lit = f > 85;
  return (
    <Scene>
      <Kicker color={C.green}>Bring online</Kicker>
      <div style={{ position: "absolute", left: 90, top: 170, width: 900, padding: "30px 36px", borderRadius: 16, backgroundColor: C.panel, fontFamily: "monospace", fontSize: 38 }}>
        <div style={{ color: C.dim, fontSize: 28, marginBottom: 12 }}>gitops/values/gpu-operator.yaml</div>
        <div><span style={{ color: C.dim }}>driver:</span></div>
        <div style={{ paddingLeft: 40 }}>{typed}<span style={{ opacity: f % 20 < 10 ? 1 : 0 }}>|</span></div>
      </div>
      <div style={{ position: "absolute", left: 540 - 12, top: 375 + dot * 90, width: 24, height: 24, borderRadius: 12, backgroundColor: C.green, opacity: dot > 0 && dot < 1 ? 1 : 0 }} />
      <div style={{ position: "absolute", left: 340, top: 480, width: 400, height: 170, borderRadius: 18, border: `3px solid ${C.green}`, backgroundColor: lit ? C.green : C.panel, color: lit ? "#000" : C.dim, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", fontWeight: 700 }}>
        <div style={{ fontSize: 34 }}>GPU node</div>
        <div style={{ fontSize: 30 }}>{lit ? "driver 595.91.07" : "no driver"}</div>
      </div>
      <div style={{ position: "absolute", left: 90, right: 90, top: 730 }}>
        <Rise at={90}><Sub style={{ color: C.text }}>Driver from a Git commit, onto a node that booted with none.</Sub></Rise>
      </div>
    </Scene>
  );
};
