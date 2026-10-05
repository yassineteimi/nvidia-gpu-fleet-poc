---
format: 1080x1080
duration: 60s
message: "Keeping GPUs useful is a job, and I rebuilt it on one rented GPU"
arc: Hook → Stakes → Pivot → Map → Proof x6 → Sign-off
audience: hiring managers on NVIDIA's Cloud Partner team, and a LinkedIn feed
mode: collaborative
---

Each scene is as long as its narration line in `voice/` (the end card takes the
remainder of the 60 s), and its key moment lands on the word that names it. Numbers
come only from `facts.json`. Motion names come from `hyperframes-animation`'s rules
index.

## Frame 1: One GPU fails

- scene: A grid of GPUs breathing in sync; one turns red and the whole grid stops and greys out
- duration: 3.93s
- poster: 3.5s
- status: animated
- src: compositions/s01-hook.html
- rules: sine-wave-loop, spring-pop-entrance (damped), waterfall-entry

"One GPU fails." then "The whole training job stops."

## Frame 2: How often

- scene: 419 counts up while 54 day ticks light along a strip
- duration: 5.67s
- poster: 3.5s
- status: animated
- src: compositions/s02-stakes.html
- rules: counting-dynamic-scale, stat-bars-and-fills

"419 interruptions in 54 days." Small: "16,384 GPUs · Meta, Llama 3 paper".

## Frame 3: The pivot

- scene: The grid converges into one glass card, NVIDIA L4, which settles into a cluster outline
- duration: 5.63s
- poster: 3.5s
- status: animated
- src: compositions/s03-pivot.html
- rules: center-outward-expansion (reversed), card-morph-anchor

"Keeping GPUs useful is a job." then "I rebuilt it on one rented GPU."

## Frame 4: A GPU's life

- scene: The six step loop draws itself; each step lights in turn, in its session colour
- duration: 5s
- poster: 4.5s
- status: animated
- src: compositions/s04-loop.html
- rules: svg-path-draw, spring-pop-entrance (damped)

## Frame 5: Bring online

- scene: The real driver pin from Git types itself; a pulse travels to the node, which turns green
- duration: 4.23s
- poster: 3.8s
- status: animated
- src: compositions/s05-online.html
- rules: discrete-text-sequence, svg-path-draw

"Driver 595.91.07, from a Git commit."

## Frame 6: Watch

- scene: A bar fills from a simulated fault to the on-call alert while the counter runs to 32 s
- duration: 5.27s
- poster: 3.8s
- status: animated
- src: compositions/s06-watch.html
- rules: stat-bars-and-fills, counting-dynamic-scale

## Frame 7: Isolate

- scene: A barrier drops on the node, its workloads slide off, two readouts land
- duration: 5.17s
- poster: 4.6s
- status: animated
- src: compositions/s07-isolate.html
- rules: reactive-displacement, counting-dynamic-scale

"Cordoned in 0.12 s. Drained in 2.5 s." Labelled "injected fault".

## Frame 8: Share

- scene: The L4 card splits into four slices; teams fill them; a third team A pod bounces off the quota
- duration: 5.27s
- poster: 4.8s
- status: animated
- src: compositions/s08-share.html
- rules: center-outward-expansion, physics-press-reaction

"One commit: 1 GPU becomes 4, in 88 s."

## Frame 9: Goodput

- scene: The goodput donut draws; 66.4% counts up; the outage slice pulls out with a 5:00 inside
- duration: 9.2s
- poster: 6.6s
- status: animated
- src: compositions/s09-goodput.html
- rules: svg-path-draw, counting-dynamic-scale, card-morph-anchor

"66.4% goodput through an injected fault." then "83% of the outage: one 5-minute safety rule."

## Frame 10: Burn-in

- scene: The real temperature line draws across 3 hours and holds at 65 °C
- duration: 5.27s
- poster: 3.8s
- status: animated
- src: compositions/s10-burnin.html
- rules: svg-path-draw, chart-scrub-readout

## Frame 11: Sign-off

- scene: Name, the promise about evidence, and the site URL, held for 3 seconds
- duration: 5.37s
- poster: 2.5s
- status: animated
- src: compositions/s11-end.html
- rules: waterfall-entry, ambient-glow-bloom
