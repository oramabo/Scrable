#!/usr/bin/env bash
# Copies the puzzle content the mobile app bundles into apps/mobile/assets.
#
#   tools/sync_assets.sh [--lang he] [--date YYYY-MM-DD] [--days 14]
#                        [--wait SECONDS] [--regen-manifests]
#
# What gets bundled (per language):
#   packs/<lang>-l1-p01/*.json + pack.json   the whole first pack of level 1
#   packs/*/pack.json                        the pack descriptor of every pack
#   daily/{easy,hard}/<date>.json            dailies for --days days from --date
#   manifests/{daily,packs}.json             the CDN manifests
#   index.json                               list of everything copied (the app
#                                            reads it instead of AssetManifest)
#
# --wait polls until the L1 pack is complete (30 puzzles + pack.json) or the
# timeout passes. --regen-manifests runs the generator's manifest command first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANG_CODE="he"
START_DATE="$(date +%F)"
DAYS=14
WAIT=0
REGEN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG_CODE="$2"; shift 2 ;;
    --date) START_DATE="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --wait) WAIT="$2"; shift 2 ;;
    --regen-manifests) REGEN=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

SRC="$ROOT/content/$LANG_CODE/puzzles"
DST="$ROOT/apps/mobile/assets/puzzles/$LANG_CODE"
L1="$LANG_CODE-l1-p01"

if [[ ! -d "$SRC" ]]; then
  echo "no content for '$LANG_CODE' at $SRC" >&2
  exit 1
fi

# Wait for the first pack to be complete.
deadline=$(( $(date +%s) + WAIT ))
while :; do
  count=$(ls "$SRC/packs/$L1"/[0-9][0-9].json 2>/dev/null | wc -l | tr -d ' ')
  if [[ -f "$SRC/packs/$L1/pack.json" && "$count" -ge 30 ]]; then break; fi
  if [[ $(date +%s) -ge $deadline ]]; then
    echo "warning: $L1 is incomplete ($count puzzles); copying what exists" >&2
    break
  fi
  echo "waiting for $L1 ($count/30)…"
  sleep 10
done

if [[ $REGEN -eq 1 ]]; then
  echo "regenerating manifests…"
  ( cd "$ROOT/tools/generate" && dart run bin/chetz_gen.dart --content "$ROOT/content" manifest --lang "$LANG_CODE" )
fi

rm -rf "$DST"
mkdir -p "$DST/packs" "$DST/daily/easy" "$DST/daily/hard" "$DST/manifests"

index_puzzles=()
index_packs=()
index_dailies=()

# 1. Whole first pack of level 1.
if [[ -d "$SRC/packs/$L1" ]]; then
  mkdir -p "$DST/packs/$L1"
  cp "$SRC/packs/$L1"/*.json "$DST/packs/$L1/"
  for f in "$DST/packs/$L1"/[0-9][0-9].json; do
    id=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$f")
    index_puzzles+=("\"$id\": \"assets/puzzles/$LANG_CODE/packs/$L1/$(basename "$f")\"")
  done
fi

# 2. pack.json of every pack.
for d in "$SRC"/packs/*/; do
  pid=$(basename "$d")
  [[ -f "$d/pack.json" ]] || continue
  mkdir -p "$DST/packs/$pid"
  cp "$d/pack.json" "$DST/packs/$pid/pack.json"
  index_packs+=("\"$pid\": \"assets/puzzles/$LANG_CODE/packs/$pid/pack.json\"")
done

# 3. Dailies for the next N days.
for ((i = 0; i < DAYS; i++)); do
  day=$(date -d "$START_DATE + $i day" +%F 2>/dev/null || date -j -v+${i}d -f %F "$START_DATE" +%F)
  for v in easy hard; do
    if [[ -f "$SRC/daily/$v/$day.json" ]]; then
      cp "$SRC/daily/$v/$day.json" "$DST/daily/$v/$day.json"
      index_dailies+=("\"$day/$v\": \"assets/puzzles/$LANG_CODE/daily/$v/$day.json\"")
    fi
  done
done

# 4. Manifests.
for m in daily.json packs.json; do
  if [[ -f "$SRC/manifests/$m" ]]; then
    cp "$SRC/manifests/$m" "$DST/manifests/$m"
  else
    echo "warning: manifest $m missing (run: dart run tools/generate/bin/chetz_gen.dart --content content manifest --lang $LANG_CODE)" >&2
  fi
done

# 5. Index.
join() { local IFS=","; echo "$*"; }
{
  echo "{"
  echo "  \"lang\": \"$LANG_CODE\","
  echo "  \"generatedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"puzzles\": {$(join "${index_puzzles[@]+"${index_puzzles[@]}"}")},"
  echo "  \"packs\": {$(join "${index_packs[@]+"${index_packs[@]}"}")},"
  echo "  \"dailies\": {$(join "${index_dailies[@]+"${index_dailies[@]}"}")}"
  echo "}"
} > "$DST/index.json"
python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$DST/index.json"

# 6. Check pubspec registration.
PUBSPEC="$ROOT/apps/mobile/pubspec.yaml"
missing=0
while IFS= read -r dir; do
  rel="${dir#"$ROOT/apps/mobile/"}/"
  if ! grep -qF -- "- $rel" "$PUBSPEC"; then
    echo "pubspec.yaml is missing asset dir: $rel" >&2
    missing=1
  fi
done < <(find "$DST" -type d)

echo "synced: ${#index_puzzles[@]} puzzles, ${#index_packs[@]} packs, ${#index_dailies[@]} dailies -> $DST"
[[ $missing -eq 0 ]] || echo "add the directories above under flutter.assets in $PUBSPEC" >&2
