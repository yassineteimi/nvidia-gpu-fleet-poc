import React from "react";
import { spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../theme";
import { Headline, Rise, Scene } from "../ui";

// Keeping GPUs useful is a job: one rented L4 drops into a Kubernetes cluster.
export const S03Rebuilt: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const drop = spring({ frame: f - 40, fps, config: { damping: 14 } });
  return (
    <Scene>
      <div style={{ position: "absolute", left: 90, right: 90, top: 110 }}>
        <Rise at={5}><Headline style={{ fontSize: 54 }}>Keeping GPUs useful is a job.</Headline></Rise>
        <Rise at={30}><Headline style={{ color: C.green, fontSize: 54 }}>I rebuilt it on one rented GPU.</Headline></Rise>
      </div>
      <div style={{ position: "absolute", left: 190, top: 470, width: 700, height: 470, border: `3px dashed ${C.dim}`, borderRadius: 24 }}>
        <div style={{ position: "absolute", top: 18, left: 26, fontSize: 30, color: C.dim }}>Kubernetes cluster</div>
        <div style={{ position: "absolute", left: 60, top: 120, width: 250, height: 250, borderRadius: 18, backgroundColor: C.panel, border: `2px solid ${C.dim}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 30, color: C.dim, textAlign: "center" }}>
          control<br />plane
        </div>
        <div style={{ position: "absolute", left: 390, top: 120 + (1 - drop) * -420, width: 250, height: 250, borderRadius: 18, backgroundColor: C.green, color: "#000", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", fontWeight: 800 }}>
          <div style={{ fontSize: 34 }}>NVIDIA</div>
          <div style={{ fontSize: 80 }}>L4</div>
        </div>
      </div>
    </Scene>
  );
};
