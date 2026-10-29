#!/usr/bin/env python3
"""Find freely licensed pictures for lexicon words (picture clues).

Pipeline per word:
  1. Wikidata SPARQL: items whose label (in the puzzle language) equals the word and that carry an image (P18),
     restricted to people, places, animals, plants, foods and objects; the item class is kept as a category.
  2. Wikimedia Commons imageinfo API: licence short name, artist and credit (extmetadata). Only files whose
     licence is in the allow-list are kept (PD, CC0, CC BY, CC BY-SA — attribution is shown in the app).
  3. Thumbnail download through Special:FilePath (width 320) into OUT_DIR/images/<wordId>.jpg.

Writes OUT_DIR/images/images.jsonl with {wordId, qid, file, license, credit, sourceUrl, category, width, height}.
Polite by design: one request at a time, exponential back-off on 429/5xx, descriptive User-Agent.

Usage: python3 -I fetch_images.py --lang he --words content/he/lexicon/words.jsonl.gz --out content/he \
         [--limit 200] [--only-proper] [--skip-license-check]
"""
import argparse
import gzip
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ChetzContentBot/1.0 (https://github.com/oramabo/Scrable; picture-clue pipeline; contact via GitHub)"
SPARQL = "https://query.wikidata.org/sparql"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
FILEPATH = "https://commons.wikimedia.org/wiki/Special:FilePath/{name}?width={width}"
ALLOWED_LICENSES = re.compile(r"^(public domain|pd|cc0|cc[ -]by(?:[ -]sa)?(?:[ -]\d\.\d)?(?: .*)?|cc-by-sa-\d\.\d|cc-by-\d\.\d)", re.I)

# Wikidata classes we accept as picture clues, with a category tag.
CLASSES = {
    "Q5": "person", "Q515": "city", "Q6256": "country", "Q23397": "lake", "Q4022": "river", "Q8502": "mountain",
    "Q16521": "taxon", "Q729": "animal", "Q2095": "food", "Q11004": "vegetable", "Q3314483": "fruit",
    "Q39546": "tool", "Q1420": "car", "Q11446": "ship", "Q17205": "aircraft", "Q811979": "building", "Q33506": "museum",
    "Q34379": "musical instrument", "Q1183543": "device", "Q7889": "video game", "Q11424": "film", "Q5398426": "tv series",
    "Q215380": "band", "Q482994": "album", "Q7366": "song", "Q41176": "building", "Q12280": "bridge", "Q179700": "statue",
}


def ssl_context():
    for candidate in (os.environ.get("SSL_CERT_FILE"), "/root/.ccr/ca-bundle.crt"):
        if candidate and os.path.exists(candidate):
            return ssl.create_default_context(cafile=candidate)
    return ssl.create_default_context()


def fetch(url, ctx, accept="application/json", retries=5, data=None):
    delay = 3.0
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept}, data=data)
        try:
            with urllib.request.urlopen(req, timeout=90, context=ctx) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 500, 502, 503, 504):
                time.sleep(delay)
                delay = min(delay * 2, 60)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            time.sleep(delay)
            delay = min(delay * 2, 60)
    return None


def read_words(path, lang, only_proper):
    out = []
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        for line in fh:
            j = json.loads(line)
            if j.get("flags", {}).get("offensive"):
                continue
            if only_proper and not j.get("flags", {}).get("proper_noun"):
                continue
            if j.get("wordCount", 1) > 2:
                continue
            label = j["display"].replace("׳", "'")
            if lang == "en":
                label = label.lower()
            out.append((j["id"], label, j))
    return out


def sparql_lookup(labels, lang, ctx):
    """Return {label: (qid, imageFileName, classQid)} for labels with an image."""
    values = " ".join('"%s"@%s' % (l.replace('"', '\\"'), lang) for l in labels)
    classes = " ".join("wd:%s" % q for q in CLASSES)
    query = f"""
    SELECT ?label ?item ?image ?cls WHERE {{
      VALUES ?label {{ {values} }}
      ?item rdfs:label ?label .
      ?item wdt:P18 ?image .
      ?item wdt:P31 ?cls .
      VALUES ?cls {{ {classes} }}
    }} LIMIT 500"""
    url = SPARQL + "?format=json&query=" + urllib.parse.quote(query)
    raw = fetch(url, ctx, accept="application/sparql-results+json")
    out = {}
    if not raw:
        return out
    for b in json.loads(raw)["results"]["bindings"]:
        label = b["label"]["value"]
        if label in out:
            continue
        image = urllib.parse.unquote(b["image"]["value"].rsplit("/", 1)[-1])
        out[label] = (b["item"]["value"].rsplit("/", 1)[-1], image, b["cls"]["value"].rsplit("/", 1)[-1])
    return out


def license_info(file_name, ctx):
    params = urllib.parse.urlencode({"action": "query", "titles": "File:" + file_name, "prop": "imageinfo",
                                     "iiprop": "url|extmetadata|size", "iiurlwidth": 320, "format": "json"})
    raw = fetch(COMMONS_API + "?" + params, ctx)
    if not raw:
        return None
    pages = json.loads(raw).get("query", {}).get("pages", {})
    for page in pages.values():
        info = (page.get("imageinfo") or [None])[0]
        if not info:
            return None
        meta = info.get("extmetadata", {})
        return {
            "license": meta.get("LicenseShortName", {}).get("value", ""),
            "artist": re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip(),
            "credit": re.sub(r"<[^>]+>", "", meta.get("Credit", {}).get("value", "")).strip(),
            "thumbUrl": info.get("thumburl"),
            "width": info.get("thumbwidth"),
            "height": info.get("thumbheight"),
            "sourceUrl": info.get("descriptionurl"),
        }
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True)
    ap.add_argument("--words", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--batch", type=int, default=60)
    ap.add_argument("--only-proper", action="store_true")
    ap.add_argument("--skip-license-check", action="store_true", help="DEV ONLY: keep images without verified licences")
    ap.add_argument("--width", type=int, default=320)
    args = ap.parse_args()

    ctx = ssl_context()
    words = read_words(args.words, args.lang, args.only_proper)
    img_dir = os.path.join(args.out, "images")
    os.makedirs(img_dir, exist_ok=True)
    index_path = os.path.join(img_dir, "images.jsonl")
    have = set()
    if os.path.exists(index_path):
        with open(index_path, encoding="utf-8") as fh:
            for line in fh:
                have.add(json.loads(line)["wordId"])
    todo = [w for w in words if w[0] not in have][: args.limit]
    print(f"{len(words)} candidate words, {len(have)} already have images, processing {len(todo)}")

    found = 0
    rejected = 0
    with open(index_path, "a", encoding="utf-8") as index:
        for i in range(0, len(todo), args.batch):
            batch = todo[i:i + args.batch]
            hits = sparql_lookup([label for _, label, _ in batch], args.lang, ctx)
            time.sleep(1.0)
            for word_id, label, _ in batch:
                hit = hits.get(label)
                if not hit:
                    continue
                qid, file_name, cls = hit
                info = None if args.skip_license_check else license_info(file_name, ctx)
                if not args.skip_license_check:
                    if not info or not ALLOWED_LICENSES.match(info["license"].strip()):
                        rejected += 1
                        continue
                    time.sleep(0.5)
                thumb = FILEPATH.format(name=urllib.parse.quote(file_name), width=args.width)
                data = fetch(thumb, ctx, accept="image/*")
                if not data:
                    rejected += 1
                    continue
                ext = ".png" if file_name.lower().endswith(".png") else ".jpg"
                local = os.path.join(img_dir, f"{word_id}{ext}")
                with open(local, "wb") as fh:
                    fh.write(data)
                record = {
                    "wordId": word_id, "qid": qid, "file": os.path.relpath(local, args.out).replace(os.sep, "/"),
                    "category": CLASSES.get(cls, cls),
                    "license": (info or {}).get("license", "unverified"),
                    "credit": (info or {}).get("artist") or (info or {}).get("credit") or "",
                    "sourceUrl": (info or {}).get("sourceUrl") or f"https://commons.wikimedia.org/wiki/File:{urllib.parse.quote(file_name)}",
                    "width": (info or {}).get("width"), "height": (info or {}).get("height"),
                }
                index.write(json.dumps(record, ensure_ascii=False) + "\n")
                index.flush()
                found += 1
                time.sleep(0.5)
            print(f"batch {i // args.batch + 1}: {found} images so far, {rejected} rejected", flush=True)
    print(f"done: {found} images, {rejected} rejected (licence or download)")


if __name__ == "__main__":
    sys.exit(main())
