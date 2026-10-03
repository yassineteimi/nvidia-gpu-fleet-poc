import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { C } from "../theme";
import { Rise, Scene, Sub, useCount } from "../ui";

// Meta's Llama 3 paper: 419 unexpected interruptions in 54 days on 16,384 GPUs.
export const S02Context: React.FC = () => {
  const f = useCurrentFrame();
  const n = useCount(419, 0, 15, 100);
  const days = 54;
  const filled = Math.round(interpolate(f, [15, 100], [0, days], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }));
  return (
    <Scene>
      <div style={{ position: "absolute", left: 90, right: 90, top: 210 }}>
        <div style={{ fontSize: 260, fontWeight: 800, color: C.red, lineHeight: 1 }}>{n}</div>
        <Rise at={10}><div style={{ fontSize: 56, fontWeight: 700, marginTop: 20 }}>interruptions in 54 days</div></Rise>
        <div style={{ display: "flex", gap: 6, marginTop: 50 }}>
          {Array.from({ length: days }).map((_, i) => (
            <div key={i} style={{ flex: 1, height: 46, borderRadius: 3, backgroundColor: i < filled ? C.red : C.panel }} />
          ))}
        </div>
        <Rise at={60}><Sub style={{ marginTop: 50 }}>one training run, 16,384 GPUs</Sub></Rise>
        <Rise at={75}><Sub style={{ fontSize: 30, marginTop: 14 }}>Source: Meta, Llama 3 paper (2024)</Sub></Rise>
      </div>
    </Scene>
  );
};
