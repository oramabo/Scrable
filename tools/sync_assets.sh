#!/usr/bin/env bash
# Copies the puzzle content the mobile app bundles into apps/mobile/assets.
#
#   tools/sync_assets.sh [--lang he] [--date YYYY-MM-DD] [--days 14]
#                        [--wait SECONDS] [--regen-manifests]
#
# What gets bundled (per language):
#   packs/<lang>-lN-p01/*.json + pack.json   the whole first pack of every level, and every picture pack
#   packs/*/pack.json                        the pack descriptor of every pack
#   daily/{easy,hard}/<date>.json            dailies for --days days from --date
#   tutorial/*.json                          the onboarding tutorial puzzles
#   images/*                                 picture-clue images (jpg/png/webp)
#   device/{lexicon,templates}.json.gz       on-device generator data (random puzzles)
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
mkdir -p "$DST/packs" "$DST/daily/easy" "$DST/daily/hard" "$DST/manifests" "$DST/tutorial" "$DST/images" "$DST/device"
# pubspec.yaml lists the images directory as an asset folder; keep it tracked even when a language has no pictures yet.
touch "$DST/images/.gitkeep"

index_puzzles=()
index_packs=()
index_dailies=()

# 1. Whole packs: pack 1 of every level (so each difficulty is playable offline from day one)
#    and every picture pack (its images are bundled anyway). Other packs ship only their
#    pack.json and are fetched from the CDN manifest when the backend is configured.
for d in "$SRC"/packs/*/; do
  pid=$(basename "$d")
  [[ -f "$d/pack.json" ]] || continue
  bundle=0
  [[ "$pid" == *-p01 ]] && bundle=1
  grep -q '"pictures": true' "$d/pack.json" && bundle=1
  [[ $bundle == 1 ]] || continue
  mkdir -p "$DST/packs/$pid"
  cp "$d"/[0-9][0-9].json "$DST/packs/$pid/"
  for f in "$DST/packs/$pid"/[0-9][0-9].json; do
    id=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$f")
    index_puzzles+=("\"$id\": \"assets/puzzles/$LANG_CODE/packs/$pid/$(basename "$f")\"")
  done
done

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

# 3b. Tutorial puzzles (ids like he-tutorial-01).
if [[ -d "$SRC/tutorial" ]]; then
  for f in "$SRC"/tutorial/*.json; do
    [[ -f "$f" ]] || continue
    cp "$f" "$DST/tutorial/$(basename "$f")"
    id=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$f")
    index_puzzles+=("\"$id\": \"assets/puzzles/$LANG_CODE/tutorial/$(basename "$f")\"")
  done
fi

# 3c. Picture-clue images (small, ~320 px). images.jsonl stays in content/.
images=0
if [[ -d "$ROOT/content/$LANG_CODE/images" ]]; then
  for f in "$ROOT/content/$LANG_CODE/images"/*; do
    case "$f" in
      *.jpg|*.jpeg|*.png|*.webp) cp "$f" "$DST/images/"; images=$((images + 1)) ;;
    esac
  done
fi

# 3d. On-device generator data: the device lexicon + layout templates
#     (gzipped JSON) that power "random puzzle" generation in the app.
device_json=""
if [[ -d "$ROOT/content/$LANG_CODE/device" ]]; then
  for name in lexicon templates; do
    f="$ROOT/content/$LANG_CODE/device/$name.json.gz"
    if [[ -f "$f" ]]; then
      cp "$f" "$DST/device/$name.json.gz"
      [[ -n "$device_json" ]] && device_json+=","
      device_json+="\"$name\": \"assets/puzzles/$LANG_CODE/device/$name.json.gz\""
    else
      echo "warning: device file $f missing (random puzzles unavailable for $LANG_CODE)" >&2
    fi
  done
fi

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
  echo "  \"dailies\": {$(join "${index_dailies[@]+"${index_dailies[@]}"}")},"
  echo "  \"device\": {$device_json}"
  echo "}"
} > "$DST/index.json"
python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$DST/index.json"

# 6. Check pubspec registration. Every registered directory must exist, or the
#    Flutter build fails, so create the ones that have no content yet.
PUBSPEC="$ROOT/apps/mobile/pubspec.yaml"
while IFS= read -r rel; do
  mkdir -p "$ROOT/apps/mobile/$rel"
done < <(grep -oE -- "- assets/puzzles/$LANG_CODE/[^ ]*/" "$PUBSPEC" | sed 's/^- //')
missing=0
while IFS= read -r dir; do
  rel="${dir#"$ROOT/apps/mobile/"}/"
  if ! grep -qF -- "- $rel" "$PUBSPEC"; then
    echo "pubspec.yaml is missing asset dir: $rel" >&2
    missing=1
  fi
done < <(find "$DST" -type d)

echo "synced: ${#index_puzzles[@]} puzzles (incl. tutorial), ${#index_packs[@]} packs, ${#index_dailies[@]} dailies, $images images, device data: ${device_json:+yes}${device_json:-no} -> $DST"
[[ $missing -eq 0 ]] || echo "add the directories above under flutter.assets in $PUBSPEC" >&2
