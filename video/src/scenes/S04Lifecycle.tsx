import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { C } from "../theme";
import { Headline, Rise, Scene } from "../ui";

// The loop every GPU in a fleet goes round, coloured by the session that built each step.
const steps = [
  { label: "Accept", color: C.purple },
  { label: "Bring online", color: C.green },
  { label: "Share and run", color: C.purple },
  { label: "Watch", color: C.blue },
  { label: "Isolate", color: C.orange },
];

export const S04Lifecycle: React.FC = () => {
  const f = useCurrentFrame();
  const cx = 540, cy = 600, rx = 330, ry = 280;
  const pos = steps.map((_, i) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / steps.length;
    return { x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a) };
  });
  const lit = (i: number) => interpolate(f, [25 + i * 22, 37 + i * 22], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <Scene>
      <div style={{ position: "absolute", left: 90, right: 90, top: 90 }}>
        <Rise at={0}><Headline>A GPU's life in a fleet</Headline></Rise>
      </div>
      <svg width={1080} height={1080} style={{ position: "absolute", left: 0, top: 0 }}>
        <ellipse cx={cx} cy={cy} rx={rx} ry={ry} fill="none" stroke={C.grey} strokeWidth={4} strokeDasharray="10 12" />
      </svg>
      {steps.map((s, i) => {
        const p = lit(i);
        return (
          <div key={s.label} style={{
            position: "absolute", left: pos[i].x - 135, top: pos[i].y - 55, width: 270, height: 110, borderRadius: 18,
            display: "flex", alignItems: "center", justifyContent: "center", fontSize: 38, fontWeight: 700,
            backgroundColor: p > 0.5 ? s.color : C.panel, color: p > 0.5 ? "#000" : C.dim,
            transform: `scale(${1 + 0.08 * p * (1 - p) * 4})`, border: `2px solid ${s.color}`,
          }}>{s.label}</div>
        );
      })}
    </Scene>
  );
};
