#!/usr/bin/env bash
# Generate the narration with a HeyGen voice, one mp3 per scene plus word timings.
# Runs on a machine signed in to HeyGen (`npx hyperframes auth login`).
#
#   VOICE_ID=<your voice id> ./scripts/make-voice.sh          all scenes
#   VOICE_ID=<your voice id> ./scripts/make-voice.sh s01 s05  only these
#
# Reads voice/lines.tsv (scene id, tab, text) and writes voice/<id>.mp3 and
# voice/<id>.words.json. SPEED (default 1.0) is passed through to HeyGen.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${VOICE_ID:-}" ]; then
  echo "Set VOICE_ID. List your own voices with:" >&2
  echo "  node ~/.claude/skills/media-use/audio/scripts/heygen-voice.mjs list" >&2
  exit 1
fi

tts=""
for dir in "$HOME/.claude/skills/media-use" "$HOME/.agents/skills/media-use"; do
  if [ -f "$dir/audio/scripts/heygen-tts.mjs" ]; then
    tts="$dir/audio/scripts/heygen-tts.mjs"
    break
  fi
done
if [ -z "$tts" ]; then
  echo "media-use skill not found. Install it with: npx hyperframes skills update media-use" >&2
  exit 1
fi

wanted=" ${*:-} "
while IFS=$'\t' read -r id text; do
  [ -z "$id" ] && continue
  if [ $# -gt 0 ] && [[ "$wanted" != *" $id "* ]]; then
    continue
  fi
  echo "== $id: $text"
  node "$tts" "$text" -o "voice/$id.mp3" --words "voice/$id.words.json" \
    --voice "$VOICE_ID" --speed "${SPEED:-1.0}" < /dev/null
done < voice/lines.tsv
