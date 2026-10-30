#!/usr/bin/env bash
# Seeds a Firebase project with the generated content: puzzle files and
# manifests in Storage (the app's CDN), and the Firestore documents the
# backend reads (dailies/*, puzzleIndex/*, manifests/*, matchPool/*).
#
#   tools/seed_firebase.sh --key PATH [--project arrowword-270f5] [--bucket NAME]
#                          [--lang he|en|all] [--only all|daily|packs|images]
#                          [--from YYYY-MM-DD] [--bank] [--skip-rules] [--skip-public]
#
# --key       service-account JSON (Firebase console → Project settings →
#             Service accounts → Generate new private key). Keep it outside the repo.
# --bucket    default <project>.firebasestorage.app
# --lang      default all (he and en)
# --only      publish only dailies, packs or images (default all)
# --from      skip dailies before this date
# --bank      also load the clue and word banks into Firestore (clues/*, words/*,
#             admin-only; ~520k documents, about 15 minutes and ~$1 of writes)
# --skip-rules   do not deploy firestore.rules, indexes and storage.rules
# --skip-public  do not make the bucket publicly readable
#
# Steps: deploy rules → make the bucket public → convert to the compact
# format, manifest + validate the content → build functions → publish every puzzle and rebuild the manifests
# → (--bank) load the clue and word banks.
# Re-running is safe: puzzles are immutable per version and documents are overwritten.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="arrowword-270f5"
BUCKET=""
KEY=""
LANGS="he en"
ONLY="all"
FROM=""
RULES=1
PUBLIC=1
BANK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --bucket) BUCKET="$2"; shift 2 ;;
    --lang) [[ "$2" == all ]] && LANGS="he en" || LANGS="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --skip-rules) RULES=0; shift ;;
    --skip-public) PUBLIC=0; shift ;;
    --bank) BANK=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

[[ -n "$KEY" && -f "$KEY" ]] || { echo "--key must point to the service-account JSON (see --help)" >&2; exit 2; }
BUCKET="${BUCKET:-$PROJECT.firebasestorage.app}"
export GOOGLE_APPLICATION_CREDENTIALS="$(cd "$(dirname "$KEY")" && pwd)/$(basename "$KEY")"
export GCLOUD_PROJECT="$PROJECT" STORAGE_BUCKET="$BUCKET"
command -v dart >/dev/null || export PATH="$PATH:$HOME/flutter/bin"

if [[ $RULES == 1 ]]; then
  echo "== deploying Firestore rules, indexes and Storage rules to $PROJECT"
  (cd "$ROOT/firebase" && firebase deploy --project "$PROJECT" --only firestore:rules,firestore:indexes,storage --non-interactive)
fi

echo "== building functions"
(cd "$ROOT/functions" && { [[ -d node_modules ]] || npm ci; } && npm run build)

if [[ $PUBLIC == 1 ]]; then
  echo "== making gs://$BUCKET publicly readable"
  (cd "$ROOT/functions" && node scripts/public-read.cjs)
fi

for lang in $LANGS; do
  echo "== $lang: compact format, manifests and validation"
  (cd "$ROOT" && dart run tools/generate/bin/chetz_gen.dart --content content convert --lang "$lang")
  (cd "$ROOT" && dart run tools/generate/bin/chetz_gen.dart --content content manifest --lang "$lang")
  (cd "$ROOT" && dart run tools/generate/bin/chetz_gen.dart --content content validate --lang "$lang")
  echo "== $lang: publishing"
  args=(--content ../content --lang "$lang" --only "$ONLY")
  [[ -n "$FROM" ]] && args+=(--from "$FROM")
  (cd "$ROOT/functions" && node scripts/publish-content.cjs "${args[@]}")
  if [[ $BANK == 1 ]]; then
    echo "== $lang: clue and word banks"
    (cd "$ROOT/functions" && node scripts/seed-bank.cjs --content ../content --lang "$lang")
  fi
done

echo
echo "Done. Point the app at the content with:"
echo "  flutter run --dart-define=CHETZ_FIREBASE=true --dart-define=CHETZ_CDN=https://storage.googleapis.com/$BUCKET"
