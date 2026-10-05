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

A 60 second video about this project for hiring managers and a LinkedIn feed, made
with HyperFrames. Motion and type follow Apple's design guidance: critically damped
springs, one moving thing at a time, translucent layered surfaces, and size-specific
tracking.

## Assets

- facts.json: every number the video may show, with its source. The only source of
  numbers.
- ../gitops/values/gpu-operator.yaml: the real driver pin shown in scene 5.
- ../gitops/values/gpu-operator-time-slicing.yaml: the real `replicas: 4` in scene 8.

## Customizations

- Stills from the middle of every scene go to Yassine before a full render.

## Notes

- Narration in Yassine's own HeyGen voice clone, one line per scene
  (`voice/script.md`), generated on his Mac with `scripts/make-voice.sh`. No
  subtitles: the on-screen text and graphics carry it. No voice credit on the end
  card. Total stays 60 s; scene lengths are trued to the recording.
- Music optional later as `assets/music.mp3`.
- Faults stay labelled "simulated" or "injected", as on the site.
- Nothing loaded from the network at render time: GSAP is vendored in
  `assets/vendor/`, fonts are the renderer's bundled Inter and JetBrains Mono.
- No em dashes, no logos of NVIDIA or Meta (naming them in text is fine).
