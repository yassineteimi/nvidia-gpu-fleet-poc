import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, FONT } from "./theme";

// Every scene fades in over 10 frames and out over the last 10.
export const Scene: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const f = useCurrentFrame();
  const { durationInFrames: d } = useVideoConfig();
  const opacity = interpolate(f, [0, 10, d - 10, d], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ backgroundColor: C.bg, fontFamily: FONT, color: C.text, opacity }}>
      {children}
    </AbsoluteFill>
  );
};

// Text that rises into place from frame `at`.
export const Rise: React.FC<{ at: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ at, children, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - at, fps, config: { damping: 200 } });
  return <div style={{ opacity: p, transform: `translateY(${(1 - p) * 30}px)`, ...style }}>{children}</div>;
};

// Small label at the top of a scene: which use case this is.
export const Kicker: React.FC<{ color: string; children: React.ReactNode }> = ({ color, children }) => (
  <div style={{ position: "absolute", top: 90, left: 90, fontSize: 30, fontWeight: 700, letterSpacing: 4, color, textTransform: "uppercase" }}>
    {children}
  </div>
);

export const Headline: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <div style={{ fontSize: 64, fontWeight: 700, lineHeight: 1.15, ...style }}>{children}</div>
);

export const Sub: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <div style={{ fontSize: 40, lineHeight: 1.3, color: C.dim, ...style }}>{children}</div>
);

// A number that counts up between two frames, eased.
export const useCount = (to: number, from: number, start: number, end: number, decimals = 0) => {
  const f = useCurrentFrame();
  const v = interpolate(f, [start, end], [from, to], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: (t) => 1 - Math.pow(1 - t, 3),
  });
  return v.toFixed(decimals);
};
