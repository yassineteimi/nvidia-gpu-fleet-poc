# Design spec

Concept: a calm operator's console. Dark glass surfaces float over a quiet field; one
thing moves at a time, settles without bounce, and the numbers carry the weight.

## Palette

| Token | Hex | Use |
|---|---|---|
| bg | `#0b0e0c` | the field, tinted toward the green |
| fg | `#f2f5ee` | headlines |
| muted | `#a3ab9f` | secondary lines |
| faint | `#6c7468` | axis labels, source paths |
| green | `#76b900` | accent; Session A |
| blue | `#6fa8dc` | Session B, Watch |
| orange | `#f6b26b` | Session C, Isolate |
| purple | `#b4a7d6` | Session D, Share, Measure, Accept |
| red | `#ff6f61` | faults and outage only |

The session colours match the site. Red is a little brighter than the site's
`#e06666` so it holds up under H.264 on a dark field.

## Type

- **Statements:** Inter 900, display sizes 88 to 120 px. Tracking -0.045em, line
  height 1.0.
- **Secondary lines:** Inter 700, 40 to 52 px. Tracking -0.02em.
- **Data and evidence:** JetBrains Mono 400/700, 24 to 30 px. Tracking +0.01em. This
  covers kickers, units, source paths and config lines.

Inter is the closest open match to Apple's system face. The mono face is the
second voice: whatever is copied from captured output is set in mono.

## Surfaces

- **Glass card:** `rgba(255,255,255,0.055)` fill, `backdrop-filter: blur(28px)
  saturate(140%)`, a 2 px `rgba(255,255,255,0.10)` border with a brighter top edge,
  28 px radius, and a deep soft shadow. Larger cards get stronger blur and shadow.
- **Background:** two radial glows (green, then blue) breathing slowly and a light
  grain. It's shared by every scene and never cut.

## Motion

- **Default:** a critically damped spring (damping 1.0) on entrances and
  repositioning, so there's no overshoot.
- **Momentum moments only:** a damping 0.8 spring when something is thrown or split,
  in scenes 8 and 9.
- **Scene exits:** each scene leaves the way it arrived, materialising out with
  blur, scale 0.97 and fade together, and the next materialises in the same way.
- **Restraint:** one focal motion at a time, and ambient motion stays below about
  0.2 Hz.

## Layout

1080 x 1080, with an 80 px safe margin. Each scene has a kicker at the top left, the
statement anchored bottom left, and the visual in the band between them. Source
paths sit at the bottom edge in faint mono.
