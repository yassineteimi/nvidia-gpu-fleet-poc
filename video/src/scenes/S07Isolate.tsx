import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { C } from "../theme";
import { Kicker, Rise, Scene, Sub } from "../ui";

// An injected XID 79: cordoned in 0.12 s, drained in 2.5 s.
export const S07Isolate: React.FC = () => {
  const f = useCurrentFrame();
  const cordon = f > 30;
  const slide = (i: number) => interpolate(f, [70 + i * 8, 100 + i * 8], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <Scene>
      <Kicker color={C.orange}>Isolate</Kicker>
      <div style={{ position: "absolute", left: 140, top: 230, width: 420, height: 420, borderRadius: 24, backgroundColor: C.panel, border: `4px solid ${cordon ? C.red : C.dim}` }}>
        <div style={{ position: "absolute", top: 18, left: 24, fontSize: 30, color: C.dim }}>GPU node</div>
        {[0, 1, 2, 3].map((i) => {
          const p = slide(i);
          return <div key={i} style={{ position: "absolute", left: 50 + (i % 2) * 170 + p * 600, top: 110 + Math.floor(i / 2) * 140, width: 150, height: 110, borderRadius: 12, backgroundColor: C.purple, opacity: 1 - p }} />;
        })}
        {cordon && <div style={{ position: "absolute", left: -4, right: -4, bottom: -60, textAlign: "center", fontSize: 32, fontWeight: 800, color: C.red, letterSpacing: 3 }}>CORDONED</div>}
      </div>
      <div style={{ position: "absolute", left: 640, top: 280 }}>
        <Rise at={30}><div style={{ fontSize: 100, fontWeight: 800, color: C.orange }}>0.12 s</div><Sub>to cordon</Sub></Rise>
        <Rise at={105}><div style={{ fontSize: 100, fontWeight: 800, color: C.orange, marginTop: 40 }}>2.5 s</div><Sub>to drain</Sub></Rise>
      </div>
      <div style={{ position: "absolute", left: 90, right: 90, top: 820 }}>
        <Rise at={120}><Sub style={{ color: C.text }}>An injected fault. No human in the loop.</Sub></Rise>
      </div>
    </Scene>
  );
};
