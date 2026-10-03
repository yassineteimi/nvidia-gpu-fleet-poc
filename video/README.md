# The PoC as a 60 second video

A brief for building a short motion-design video about this project, for hiring
managers and a LinkedIn audience. Nothing here is built yet.

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
- Render locally: Chromium is at `/opt/pw-browsers/chromium` in Claude's cloud
  containers, and Remotion can use it through `--browser-executable`. Fonts bundled in
  the project, nothing loaded from the network at render time.
- Output `video/out/gpu-fleet-poc-60s.mp4`, plus a poster frame
  `video/out/poster.png` for the LinkedIn post. Keep `out/` out of Git if the file is
  large; attach it to a GitHub release instead.

## Prompt for the next session

> Read `video/README.md`, `video/storyboard.md` and `video/facts.json` in this
> repository, and skim `docs/use-cases.md` and `docs/04-goodput-and-burn-in.md` for
> context. Build the video as a Remotion project in `video/`: one composition,
> 1080 x 1080, 30 fps, 60 seconds, one React component per storyboard scene. Use only
> numbers from `facts.json`. Render it to `video/out/gpu-fleet-poc-60s.mp4` with the
> local Chromium, extract a poster frame, and send me both files. Then send me stills of
> every scene's middle frame so I can review the text before any polishing.
