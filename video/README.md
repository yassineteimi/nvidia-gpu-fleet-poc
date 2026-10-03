# The PoC as a 60 second video

A short motion-design video about this project, for hiring managers and a LinkedIn
audience. Built and rendered: [`dist/gpu-fleet-poc-60s.mp4`](dist/gpu-fleet-poc-60s.mp4)
(1080 x 1080, 30 fps, 60 s, H.264) and the poster frame
[`dist/poster.png`](dist/poster.png).

**Decided:** made in code with [Remotion](https://www.remotion.dev/) (React), rendered
to MP4 locally; square 1080 x 1080 at 30 fps, about 60 seconds; captions on screen,
music optional, no voiceover.

| File | What's in it |
|---|---|
| `storyboard.md` | The 11 scenes, timing, on-screen text, motion and the look |
| `facts.json` | Every number the video may show, each with the committed file it comes from |

## Rules for whoever builds it

- Only numbers from `facts.json`, worded as there. Faults stay labelled "simulated" or
  "injected"; the site is careful about that and the video must be too.
- Captions short, in plain English, written for someone who doesn't run GPU clusters.
  No buzzwords, no exclamation marks.
- Render locally, with fonts bundled in the project and nothing loaded from the network
  at render time.
- The finished files go in `dist/`; `out/` holds build output and stays out of Git.

## Rebuilding it

```sh
cd video
npm ci
npm run render     # writes out/gpu-fleet-poc-60s.mp4
npm run poster     # writes out/poster.png
npm run finalize   # re-encodes to yuv420p with faststart into dist/, needs ffmpeg on the PATH
```

Each scene is one component in `src/scenes/`, timed in `src/Video.tsx`. Remotion
needs a Chrome headless shell, not a full Chromium: in Claude's cloud containers that's
`/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell`, which the
scripts point at. Elsewhere, drop `--browser-executable` and Remotion downloads its own.
The render writes `yuvj420p`; `finalize` converts to `yuv420p`, which every player and
LinkedIn accept.

## The prompt this was built from

> Read `video/README.md`, `video/storyboard.md` and `video/facts.json` in this
> repository, and skim `docs/use-cases.md` and `docs/04-goodput-and-burn-in.md` for
> context. Build the video as a Remotion project in `video/`: one composition,
> 1080 x 1080, 30 fps, 60 seconds, one React component per storyboard scene. Use only
> numbers from `facts.json`. Render it to `video/out/gpu-fleet-poc-60s.mp4` with the
> local Chromium, extract a poster frame, and send me both files. Then send me stills of
> every scene's middle frame so I can review the text before any polishing.
