import React from "react";
import facts from "../../facts.json";
import { C } from "../theme";
import { Rise, Scene, Sub } from "../ui";

export const S11End: React.FC = () => (
  <Scene>
    <div style={{ position: "absolute", left: 90, right: 90, top: 300 }}>
      <div style={{ width: 120, height: 10, backgroundColor: C.green, marginBottom: 50 }} />
      <Rise at={0}><div style={{ fontSize: 80, fontWeight: 800 }}>Yassine Teimi</div></Rise>
      <Rise at={10}><Sub style={{ marginTop: 16 }}>GPU fleet operations on Kubernetes</Sub></Rise>
      <Rise at={25}><div style={{ fontSize: 40, marginTop: 70 }}>Every number links to captured output.</div></Rise>
      <Rise at={35}><div style={{ fontSize: 34, marginTop: 30, color: C.green }}>{facts.links.site.replace("https://", "")}</div></Rise>
    </div>
  </Scene>
);
