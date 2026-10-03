import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { C } from "../theme";
import { Kicker, Rise, Scene, Sub, useCount } from "../ui";

// A simulated XID 79 reached Alertmanager as a critical alert in 32 seconds.
export const S06Watch: React.FC = () => {
  const f = useCurrentFrame();
  const fill = interpolate(f, [20, 100], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const secs = useCount(32, 0, 20, 100);
  const fired = f > 100;
  return (
    <Scene>
      <Kicker color={C.blue}>Watch</Kicker>
      <div style={{ position: "absolute", left: 90, right: 90, top: 200, fontSize: 240, fontWeight: 800, color: C.blue, lineHeight: 1 }}>
        {secs} s
      </div>
      <div style={{ position: "absolute", left: 90, top: 560, width: 900, height: 24, borderRadius: 12, backgroundColor: C.panel }}>
        <div style={{ width: `${fill * 100}%`, height: "100%", borderRadius: 12, backgroundColor: C.blue }} />
      </div>
      <div style={{ position: "absolute", left: 70, top: 540, width: 64, height: 64, borderRadius: 32, backgroundColor: C.red }} />
      <div style={{ position: "absolute", left: 890, top: 532, width: 130, height: 80, borderRadius: 18, backgroundColor: fired ? C.red : C.panel, border: `3px solid ${C.red}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, fontWeight: 800, color: fired ? "#000" : C.red }}>ALERT</div>
      <div style={{ position: "absolute", left: 60, top: 630, fontSize: 28, color: C.dim }}>simulated GPU fault</div>
      <div style={{ position: "absolute", right: 60, top: 630, fontSize: 28, color: C.dim }}>on-call alert</div>
      <div style={{ position: "absolute", left: 90, right: 90, top: 780 }}>
        <Rise at={100}><Sub style={{ color: C.text }}>From a simulated GPU fault to the on-call alert.</Sub></Rise>
      </div>
    </Scene>
  );
};
