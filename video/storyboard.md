# Storyboard: 60 seconds, 1080 x 1080, 30 fps

Captions carry the story; most people will watch muted. One idea per scene, at most
about 10 words on screen at a time, and every number from `facts.json`. Faults are
always labelled "simulated" or "injected", as on the site.

| # | Time | On screen | Motion |
|---|---|---|---|
| 1 | 0 to 5 s | **One GPU fails. The whole training job stops.** | A grid of small green squares pulsing in sync, a training job. One square turns red and the whole grid freezes and greys out. |
| 2 | 5 to 10 s | **419 interruptions in 54 days.** Small: *16,384 GPUs. Meta, Llama 3 paper* | The counter rolls up to 419 over a calendar strip of 54 days. |
| 3 | 10 to 15 s | **Keeping GPUs useful is a job. I rebuilt it on one rented GPU.** | The grid collapses into one card labelled NVIDIA L4, which drops into a Kubernetes cluster outline. |
| 4 | 15 to 21 s | The lifecycle: **Accept, Bring online, Share and run, Watch, Isolate** | The six-step loop from `docs/use-cases.md`, drawn left to right; each step lights up in turn. Same colours as the site. |
| 5 | 21 to 26 s | **Bring online:** *driver 595.91.07, from a Git commit* | A commit line types itself, then flows as a dot into the GPU node; the node turns green. |
| 6 | 26 to 31 s | **Watch:** *simulated GPU fault to on-call alert, 32 s* | A timeline bar fills from "fault" to a bell icon; the counter runs to 32 s. |
| 7 | 31 to 37 s | **Isolate:** *cordoned in 0.12 s, drained in 2.5 s* | The node gets a barrier; small workload blocks slide off it. Two stopwatch readouts. |
| 8 | 37 to 43 s | **Share:** *one commit, 1 GPU becomes 4. The quota says no to a third pod.* | The L4 card splits into four slices; two teams' blocks fill them; a third block bounces off with "quota". |
| 9 | 43 to 51 s | **66.4% goodput through an injected fault.** Then: *83% of the loss: one 5-minute safety rule* | The pie from Session D draws itself; the red outage slice pulls out and a 5:00 timer sits inside it. |
| 10 | 51 to 56 s | **Burn-in: 3 hours at full load. 65 °C, flat. No errors.** | The temperature line from `facts.json` draws itself across a 3 hour axis. |
| 11 | 56 to 60 s | **Yassine Teimi.** *Every number links to captured output.* The site URL | Calm end card on the dark background, NVIDIA green accent, URL readable for 3 s. |

## Look

- Background `#1e2129`, text `#e6e6e6`, accent NVIDIA green `#76b900`.
- Session colours, as on the site: A green `#76b900`, B blue `#6fa8dc`, C orange `#f6b26b`,
  D purple `#b4a7d6`, faults and outage red `#e06666`.
- One sans-serif typeface (Inter or similar, bundled locally, not fetched), large sizes:
  headline 64 px or more, secondary lines 40 px.
- Flat shapes and lines, no stock footage, no 3D, no logos of NVIDIA or Meta (naming
  them in text is fine).

## Music

Captions only. If music is added, a calm instrumental track with a licence that allows
LinkedIn use, supplied by Yassine as `video/public/music.mp3`. The video must work
silent.
