# The 60 second video

The project in 60 seconds, for people who don't run GPU clusters: 1080 x 1080, 30 fps,
narrated in my own voice (a HeyGen clone of it), no subtitles. It's built with
[HyperFrames](https://hyperframes.heygen.com), which renders HTML and GSAP animation to
MP4.

The rendered video is [`../docs/assets/video/gpu-fleet-poc.mp4`](../docs/assets/video/gpu-fleet-poc.mp4).

| File | What's in it |
|---|---|
| `facts.json` | Every number the video shows, with the committed file it comes from |
| `BRIEF.md` | What the video is for and the rules it keeps |
| `frame.md` | The design spec: palette, type, surfaces, motion |
| `STORYBOARD.md` | The 11 scenes, each with its file and the motion rules it uses |
| `index.html` | The main composition: shared background, motion helpers, scene slots, narration |
| `compositions/` | One file per scene |
| `voice/` | The narration: `lines.tsv` (one line per scene), an mp3 and word timings per line |
| `scripts/make-voice.sh` | Regenerates the narration with HeyGen; needs a HeyGen login |
| `assets/vendor/gsap.min.js` | GSAP 3.14.2, vendored so nothing loads from the network |

## How it's made

- **Only captured numbers.** Every figure on screen or in the narration is in
  `facts.json`, with its source. Faults are labelled "simulated" or "injected", as
  on the site.
- **Real data drawn.**
  - Scene 5 shows the actual driver pin from `gitops/values/gpu-operator.yaml`.
  - Scene 9's donut uses the six numbers in `session-d-goodput.json`.
  - Scene 10 draws the 19 temperature readings from the burn-in.
- **Timed to the voice.** Each scene is as long as its spoken line, and its key
  moment lands on the word that names it: the GPU turns red on "fails", the
  counter reaches 32 on "32 seconds", the outage slice comes forward on "Most of
  the outage". The end card takes what's left of the 60 s.
- **Motion.** Entrances use a critically damped spring, so nothing overshoots,
  except the GPU splitting into four in scene 8, which gets a little bounce. One
  thing moves at a time, and each scene leaves the way it arrived.
- **Type.** Statements are set in Inter 900. Anything copied from captured output is
  set in JetBrains Mono: config lines, units and labels.

## Rebuilding it

```sh
cd video
npm run check
npx hyperframes render -o renders/gpu-fleet-poc.mp4 --fps 30 --quality delivery
```

Rendering needs `ffmpeg` and `ffprobe` on the PATH, built with the `afade` and
`alimiter` audio filters. `check` runs HyperFrames' lint, runtime, layout, motion and
contrast checks; it should pass with 0 errors. Inter and JetBrains Mono are fetched
from Google Fonts once at build time and cached.

The copy in `docs/assets/video/` is re-encoded for the web from the render:

```sh
ffmpeg -i renders/gpu-fleet-poc.mp4 -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -c:a copy -movflags +faststart ../docs/assets/video/gpu-fleet-poc.mp4
```

To change a line of narration, edit `voice/lines.tsv`, run
`VOICE_ID=<id> ./scripts/make-voice.sh <scene id>` on a machine signed in to HeyGen,
then re-time that scene in `index.html` and its composition.
