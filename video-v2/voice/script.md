# Narration

Spoken in Yassine's voice (his HeyGen voice clone), no subtitles. One line per scene;
`lines.tsv` holds the same text and is what `../scripts/make-voice.sh` reads. Numbers
match `../../video/facts.json` and what's on screen.

| Scene | On screen | Spoken |
|---|---|---|
| 1 | One GPU fails. The whole job stops. | When one GPU fails, the whole training job stops. |
| 2 | 419 interruptions in 54 days | Training Llama 3, Meta counted 419 interruptions in 54 days. |
| 3 | I rebuilt it on one rented GPU. | Keeping GPUs useful is a job. I rebuilt it on one rented GPU. |
| 4 | A GPU's life in a fleet | A GPU in a fleet lives in a loop. Here's how each step works. |
| 5 | The driver comes from Git. | The driver version is pinned in Git. Nobody installs it by hand. |
| 6 | 32 s, simulated | A simulated GPU fault reached the on-call alert in 32 seconds. |
| 7 | 0.12 s, 2.5 s, injected fault | On an injected fault, a controller isolated the node in 2.5 seconds. |
| 8 | 1 GPU becomes 4. | One commit splits the GPU four ways, and every team stays inside its quota. |
| 9 | 66.4% goodput, then 83% of the outage | I also measured what a failure costs: 66.4 percent goodput. Most of the outage came from one five-minute safety rule. |
| 10 | 3 hours at full load. | New hardware earns its place first: three hours at full load, no errors. |
| 11 | Yassine Teimi | I'm Yassine Teimi. Every number here comes from captured output. |

138 words. At a calm pace that's about 55 seconds of speech, which leaves short
pauses between scenes inside 60 seconds. Scene lengths get trued to the real
recording; the total stays 60.
