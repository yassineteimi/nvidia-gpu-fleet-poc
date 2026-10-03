import React from "react";
import { interpolate, interpolateColors, useCurrentFrame } from "remotion";
import { C } from "../theme";
import { Headline, Rise, Scene } from "../ui";

// A training job: a grid of GPUs pulsing in step. One fails, and they all stop.
export const S01Hook: React.FC = () => {
  const f = useCurrentFrame();
  const cols = 10, rows = 7, size = 58, gap = 14;
  const failed = 34;
  const failAt = 55;
  const stopAt = 70;
  const w = cols * size + (cols - 1) * gap;
  const pulse = 0.65 + 0.35 * Math.sin(f / 5);
  const stop = interpolate(f, [stopAt, stopAt + 20], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <Scene>
      <div style={{ position: "absolute", top: 130, left: (1080 - w) / 2, width: w, display: "flex", flexWrap: "wrap", gap }}>
        {Array.from({ length: cols * rows }).map((_, i) => {
          const isFailed = i === failed && f >= failAt;
          const color = isFailed ? C.red : interpolateColors(stop, [0, 1], [C.green, C.grey]);
          const opacity = isFailed ? 1 : f < stopAt ? pulse : interpolate(stop, [0, 1], [pulse, 0.5]);
          return <div key={i} style={{ width: size, height: size, borderRadius: 8, backgroundColor: color, opacity }} />;
        })}
      </div>
      <div style={{ position: "absolute", left: 90, right: 90, top: 740 }}>
        <Rise at={failAt}><Headline style={{ fontSize: 56 }}>One GPU fails.</Headline></Rise>
        <Rise at={stopAt + 5}><Headline style={{ color: C.red, fontSize: 56 }}>The whole training job stops.</Headline></Rise>
      </div>
    </Scene>
  );
};
