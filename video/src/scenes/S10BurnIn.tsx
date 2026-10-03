import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import facts from "../../facts.json";
import { C } from "../theme";
import { Kicker, Rise, Scene, Sub } from "../ui";

// Three hours at full load: temperature, one real sample every 10 minutes.
const temps = facts.session_d.burn_in.temperature_every_10_min_c;

export const S10BurnIn: React.FC = () => {
  const f = useCurrentFrame();
  const draw = interpolate(f, [15, 95], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const x0 = 140, x1 = 980, y0 = 720, y1 = 300; // y axis 30 to 80 C
  const x = (i: number) => x0 + (i / (temps.length - 1)) * (x1 - x0);
  const y = (t: number) => y0 - ((t - 30) / 50) * (y0 - y1);
  const n = Math.max(2, Math.ceil(draw * temps.length));
  const pts = temps.slice(0, n).map((t, i) => `${x(i)},${y(t)}`).join(" ");
  return (
    <Scene>
      <Kicker color={C.purple}>Burn-in</Kicker>
      <div style={{ position: "absolute", left: 90, right: 90, top: 150 }}>
        <Rise at={0}><div style={{ fontSize: 56, fontWeight: 700 }}>3 hours at full load.</div></Rise>
      </div>
      <svg width={1080} height={1080} style={{ position: "absolute" }}>
        <line x1={x0} y1={y0} x2={x1} y2={y0} stroke={C.grey} strokeWidth={3} />
        <line x1={x0} y1={y(65)} x2={x1} y2={y(65)} stroke={C.grey} strokeWidth={2} strokeDasharray="8 10" />
        <polyline points={pts} fill="none" stroke={C.red} strokeWidth={8} strokeLinejoin="round" />
        <text x={x0} y={y0 + 50} fill={C.dim} fontSize={30}>0 h</text>
        <text x={x1 - 50} y={y0 + 50} fill={C.dim} fontSize={30}>3 h</text>
        <text x={x0 - 10} y={y(65) - 18} fill={C.dim} fontSize={30}>65 °C</text>
      </svg>
      <div style={{ position: "absolute", left: 90, right: 90, top: 830 }}>
        <Rise at={95}><div style={{ fontSize: 50, fontWeight: 700 }}>65 °C, flat. No throttling, no errors.</div></Rise>
      </div>
    </Scene>
  );
};
