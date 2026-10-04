---
workflow: general-video
flow: companion
storyboard: yes
message: "Keeping GPUs useful is a job, and I rebuilt it on one rented GPU"
destination: linkedin-feed
aspect: 1080x1080
language: en
audience: hiring managers on NVIDIA's Cloud Partner team, and a LinkedIn feed
length: 60s
angle: proof
---

## Intent

Version 2 of the 60 second video in `../video/`, rebuilt with HyperFrames instead of
Remotion, with motion and type following Apple's design guidance: critically damped
springs, one moving thing at a time, translucent layered surfaces, and size-specific
tracking. The story, the scenes and every number stay as in v1.

## Assets

- ../video/facts.json: every number the video may show, with its source. The only
  source of numbers.
- ../video/storyboard.md: the 11 scenes and their timing, carried over.
- ../gitops/values/gpu-operator.yaml: the real driver pin shown in scene 5.
- ../gitops/values/gpu-operator-time-slicing.yaml: the real `replicas: 4` in scene 8.

## Customizations

- Stills from the middle of every scene go to Yassine before the full render.

## Notes

- Captions only, no voiceover. Music optional later as `assets/music.mp3`; the video
  must work silent.
- Faults stay labelled "simulated" or "injected", as on the site.
- Nothing loaded from the network at render time: GSAP is vendored in
  `assets/vendor/`, fonts are the renderer's bundled Inter and JetBrains Mono.
- No em dashes, no logos of NVIDIA or Meta (naming them in text is fine).
