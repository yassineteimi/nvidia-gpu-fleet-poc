import React from "react";
import { Series } from "remotion";
import "@fontsource/inter/400.css";
import "@fontsource/inter/700.css";
import "@fontsource/inter/800.css";
import { S01Hook } from "./scenes/S01Hook";
import { S02Context } from "./scenes/S02Context";
import { S03Rebuilt } from "./scenes/S03Rebuilt";
import { S04Lifecycle } from "./scenes/S04Lifecycle";
import { S05Online } from "./scenes/S05Online";
import { S06Watch } from "./scenes/S06Watch";
import { S07Isolate } from "./scenes/S07Isolate";
import { S08Share } from "./scenes/S08Share";
import { S09Goodput } from "./scenes/S09Goodput";
import { S10BurnIn } from "./scenes/S10BurnIn";
import { S11End } from "./scenes/S11End";

// Scene lengths in frames at 30 fps, following storyboard.md. They add up to 1800, 60 s.
export const SCENES: [React.FC, number][] = [
  [S01Hook, 150],
  [S02Context, 150],
  [S03Rebuilt, 150],
  [S04Lifecycle, 180],
  [S05Online, 150],
  [S06Watch, 150],
  [S07Isolate, 180],
  [S08Share, 180],
  [S09Goodput, 240],
  [S10BurnIn, 150],
  [S11End, 120],
];
export const TOTAL = SCENES.reduce((s, [, d]) => s + d, 0);

export const Video: React.FC = () => (
  <Series>
    {SCENES.map(([C, d], i) => (
      <Series.Sequence key={i} durationInFrames={d}>
        <C />
      </Series.Sequence>
    ))}
  </Series>
);
