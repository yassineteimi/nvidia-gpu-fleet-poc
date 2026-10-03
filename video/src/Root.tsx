import React from "react";
import { Composition } from "remotion";
import { FPS } from "./theme";
import { TOTAL, Video } from "./Video";

export const Root: React.FC = () => (
  <Composition id="GpuFleetPoc" component={Video} durationInFrames={TOTAL} fps={FPS} width={1080} height={1080} />
);
