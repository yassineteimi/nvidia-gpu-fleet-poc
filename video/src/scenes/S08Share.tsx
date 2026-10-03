import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../theme";
import { Kicker, Rise, Scene, Sub } from "../ui";

// One commit: the L4 shows up as 4 GPUs in 88 s. Team A gets two, team B one, and
// team A's third pod bounces off its quota.
export const S08Share: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const split = interpolate(f, [15, 40], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const fillAt = [55, 70, 85];
  const owners = [C.purple, C.purple, C.blue];
  const bounce = spring({ frame: f - 110, fps, config: { damping: 8 } });
  const w = 180, gap = 20 * split, total = 4 * w + 3 * gap, x0 = (1080 - total) / 2;
  return (
    <Scene>
      <Kicker color={C.purple}>Share</Kicker>
      <div style={{ position: "absolute", left: 90, right: 90, top: 160 }}>
        <Rise at={0}><div style={{ fontSize: 56, fontWeight: 700 }}>One commit: 1 GPU becomes 4, in 88 s.</div></Rise>
      </div>
      {[0, 1, 2, 3].map((i) => {
        const filled = i < 3 && f > fillAt[i];
        return (
          <div key={i} style={{ position: "absolute", left: x0 + i * (w + gap), top: 400, width: w, height: 260, borderRadius: split > 0.5 ? 14 : 0, backgroundColor: filled ? owners[i] : C.panel, border: `3px solid ${C.green}` }}>
            {filled && <div style={{ position: "absolute", bottom: 14, width: "100%", textAlign: "center", fontSize: 28, fontWeight: 700, color: "#000" }}>{i < 2 ? "team A" : "team B"}</div>}
          </div>
        );
      })}
      {f > 100 && (
        <div style={{ position: "absolute", left: 450 - bounce * 300, top: 720, width: 180, height: 120, borderRadius: 14, backgroundColor: C.purple, opacity: interpolate(f, [100, 150], [1, 0.35], { extrapolateRight: "clamp" }), display: "flex", alignItems: "center", justifyContent: "center", fontSize: 26, fontWeight: 700, color: "#000", border: `4px solid ${C.red}` }}>team A, 3rd</div>
      )}
      {f > 118 && <div style={{ position: "absolute", left: 360, top: 755, fontSize: 40, fontWeight: 800, color: C.red }}>refused: quota is 2</div>}
      <div style={{ position: "absolute", left: 90, right: 90, top: 880 }}>
        <Rise at={120}><Sub style={{ color: C.text }}>A team's third GPU pod: refused by its quota.</Sub></Rise>
      </div>
    </Scene>
  );
};
