import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import facts from "../../facts.json";
import { C } from "../theme";
import { Kicker, Rise, Scene, Sub, useCount } from "../ui";

// Where the 1383 seconds of the interrupted training run went.
const b = facts.session_d.goodput_breakdown_s;
const parts = [
  { v: b.useful, c: C.green },
  { v: b.outage, c: C.red },
  { v: b.redone, c: C.orange },
  { v: b.checkpoint, c: C.blue },
  { v: b.other + b.restore, c: C.grey },
];
const total = parts.reduce((s, p) => s + p.v, 0);

const arc = (cx: number, cy: number, r: number, a0: number, a1: number) => {
  const p = (a: number) => [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  const [x0, y0] = p(a0), [x1, y1] = p(a1);
  return `M ${x0} ${y0} A ${r} ${r} 0 ${a1 - a0 > Math.PI ? 1 : 0} 1 ${x1} ${y1}`;
};

export const S09Goodput: React.FC = () => {
  const f = useCurrentFrame();
  const sweep = interpolate(f, [10, 70], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const pop = interpolate(f, [130, 150], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const pct = useCount(facts.session_d.goodput.value, 0, 10, 70, 1);
  const cx = 330, cy = 560, r = 190;
  let a = -Math.PI / 2;
  return (
    <Scene>
      <Kicker color={C.purple}>Goodput</Kicker>
      <svg width={1080} height={1080} style={{ position: "absolute" }}>
        {parts.map((p, i) => {
          const a0 = a, a1 = a + (p.v / total) * 2 * Math.PI;
          a = a1;
          const end = Math.min(a1, -Math.PI / 2 + sweep * 2 * Math.PI);
          if (end <= a0) return null;
          const mid = (a0 + a1) / 2, off = i === 1 ? pop * 40 : 0;
          return <path key={i} d={arc(cx + off * Math.cos(mid), cy + off * Math.sin(mid), r, a0, end - 0.004)} stroke={p.c} strokeWidth={110} fill="none" />;
        })}
      </svg>
      <div style={{ position: "absolute", left: 90, top: 860, display: "flex", gap: 34, fontSize: 28, color: C.dim }}>
        {[["useful", C.green], ["outage", C.red], ["redone", C.orange], ["checkpoints", C.blue]].map(([l, c]) => (
          <div key={l} style={{ display: "flex", alignItems: "center", gap: 10 }}><div style={{ width: 22, height: 22, borderRadius: 4, backgroundColor: c }} />{l}</div>
        ))}
      </div>
      <div style={{ position: "absolute", left: cx - 120, top: cy - 50, width: 240, textAlign: "center", fontSize: 72, fontWeight: 800 }}>{pct}%</div>
      <div style={{ position: "absolute", left: 610, top: 300, width: 420 }}>
        <Rise at={50}><div style={{ fontSize: 50, fontWeight: 700 }}>of the run was useful</div></Rise>
        <Rise at={65}><Sub style={{ fontSize: 34, marginTop: 10 }}>through an injected GPU fault</Sub></Rise>
        <Rise at={130}><div style={{ fontSize: 120, fontWeight: 800, color: C.red, marginTop: 70 }}>83%</div></Rise>
        <Rise at={140}><Sub style={{ fontSize: 34, color: C.text }}>of the loss: one 5-minute safety rule</Sub></Rise>
      </div>
    </Scene>
  );
};
