# The 60 second video, v2

The same story as [`../video/`](../video/), rebuilt with
[HyperFrames](https://hyperframes.heygen.com) (HTML and GSAP, rendered to MP4) instead of
Remotion. The motion and type follow Apple's design guidance for fluid interfaces.
1080 x 1080, 30 fps, 60 s, captions only.

Status: built and checked. Stills of every scene are in `review/`; not yet rendered.

| File | What's in it |
|---|---|
| `BRIEF.md` | What the video is for and the rules it keeps |
| `frame.md` | The design spec: palette, type, surfaces, motion |
| `STORYBOARD.md` | The 11 scenes, each with its file and the motion rules it uses |
| `index.html` | The main composition: shared background, motion helpers, scene slots |
| `compositions/` | One file per scene |
| `assets/vendor/gsap.min.js` | GSAP 3.14.2, vendored so nothing loads from the network |

## What changed from v1

- **Springs, not fades.** Entrances use a critically damped spring (damping 1.0), so
  nothing overshoots. The one exception is the GPU splitting into four in scene 8,
  which has momentum and gets a damping 0.8 spring.
- **One focal motion at a time,** and each scene leaves the way it arrived: blur,
  scale and fade together.
- **Glass surfaces** over one shared background that never cuts between scenes.
- **Two voices for type.** Statements are set in Inter 900 with tracking tightened
  for display sizes. Anything copied from captured output is set in JetBrains Mono:
  config lines, units and labels.
- **Real data drawn.**
  - Scene 5 shows the actual driver pin from `gitops/values/gpu-operator.yaml`.
  - Scene 9's donut uses the six numbers in `session-d-goodput.json`.
  - Scene 10 draws the 19 temperature readings from the burn-in.
- **"No thermal throttling"** replaces v1's "no throttling". The burn-in ran
  power-capped most of the time, which is throttling by power, not by heat.

Every number still comes from [`../video/facts.json`](../video/facts.json).

## Rebuilding it

```sh
cd video-v2
npm run check
npm run render
```

`check` runs HyperFrames' lint, runtime, layout, motion and contrast checks; it should
pass with 0 errors. Inter and JetBrains Mono are fetched from Google Fonts once at build
time and cached; after that the build is offline.
