#!/usr/bin/env python3
"""Build large per-language word banks (2–16 letters) from free sources.

Hebrew: Mordo answers (content/he/lexicon), Hebrew Wiktionary titles, Hebrew Wikipedia single-word titles.
English: ENABLE, WordNet lemmas (English Wiktionary titles were tried and rejected: they mix in every Latin-script language).

Output: OUT/wordbank/words-<len>.txt (one normalised word per line, sorted, deduplicated),
        OUT/wordbank/bank.jsonl.gz ({word, length, sources[]}), OUT/wordbank/stats.json.
Words in the bank without clues are NOT used by the generator (which needs clues); the bank feeds
clue writing, validation and future content.

Usage: python3 -I build_wordbank.py --lang he --out content/he --lexicon content/he/lexicon/words.jsonl.gz \
         --titles hewiktionary-latest-all-titles-in-ns0.gz --titles hewiki-latest-all-titles-in-ns0.gz
"""
import argparse
import gzip
import json
import os
import re
import sys
from collections import defaultdict

HE_LETTERS = set("אבגדהוזחטיכלמנסעפצקרשתךםןףץ")
FINAL_TO_BASE = {"ך": "כ", "ם": "מ", "ן": "נ", "ף": "פ", "ץ": "צ"}
MIN_LEN, MAX_LEN = 2, 16


def normalise_he(title: str):
    t = title.strip()
    if not t or " " in t or "-" in t or "_" in t:
        return None
    if "(" in t or ":" in t or "," in t or "." in t or '"' in t:
        return None
    key = []
    for ch in t:
        if ch in "׳'":
            if key and key[-1] in "גזצתד":
                key[-1] = key[-1] + "׳"
            continue
        if ch not in HE_LETTERS:
            return None
        key.append(FINAL_TO_BASE.get(ch, ch))
    n = len(key)
    if n < MIN_LEN or n > MAX_LEN:
        return None
    return "".join(key)


def normalise_en(title: str):
    t = title.strip().lower()
    if not re.fullmatch(r"[a-z]+", t):
        return None
    if len(t) < MIN_LEN or len(t) > MAX_LEN:
        return None
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--lexicon", help="existing lexicon words.jsonl.gz to include")
    ap.add_argument("--titles", action="append", default=[], help="Wikimedia all-titles-in-ns0.gz dumps")
    ap.add_argument("--plain", action="append", default=[], help="plain word lists (one per line)")
    ap.add_argument("--wordnet", help="WordNet dict directory (English lemmas)")
    args = ap.parse_args()
    norm = normalise_he if args.lang == "he" else normalise_en

    bank = defaultdict(set)  # word -> sources
    if args.lexicon:
        with gzip.open(args.lexicon, "rt", encoding="utf-8") as fh:
            for line in fh:
                j = json.loads(line)
                if j.get("wordCount", 1) == 1:
                    w = j["canonical"]
                    if MIN_LEN <= len(w.replace("׳", "")) <= MAX_LEN:
                        bank[w].add("lexicon")
    for path in args.titles:
        name = os.path.basename(path).split("-")[0]
        with gzip.open(path, "rt", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                w = norm(line.rstrip("\n").replace("_", " "))
                if w:
                    bank[w].add(name)
    for path in args.plain:
        name = os.path.basename(path).split(".")[0]
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                w = norm(line)
                if w:
                    bank[w].add(name)
    if args.wordnet:
        for pos in ("noun", "verb", "adj", "adv"):
            with open(os.path.join(args.wordnet, f"index.{pos}"), encoding="latin-1") as fh:
                for line in fh:
                    if line.startswith(" "):
                        continue
                    w = norm(line.split(" ", 1)[0])
                    if w:
                        bank[w].add("wordnet")

    out_dir = os.path.join(args.out, "wordbank")
    os.makedirs(out_dir, exist_ok=True)
    by_len = defaultdict(list)
    for w in bank:
        by_len[len(w.replace("׳", ""))].append(w)
    for n, words in by_len.items():
        words.sort()
        with open(os.path.join(out_dir, f"words-{n:02d}.txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(words) + "\n")
    with gzip.open(os.path.join(out_dir, "bank.jsonl.gz"), "wt", encoding="utf-8") as fh:
        for w in sorted(bank):
            fh.write(json.dumps({"word": w, "length": len(w.replace("׳", "")), "sources": sorted(bank[w])}, ensure_ascii=False) + "\n")
    stats = {"lang": args.lang, "total": len(bank), "byLength": {str(n): len(by_len[n]) for n in sorted(by_len)},
             "bySource": {}}
    for sources in bank.values():
        for s in sources:
            stats["bySource"][s] = stats["bySource"].get(s, 0) + 1
    with open(os.path.join(out_dir, "stats.json"), "w", encoding="utf-8") as fh:
        json.dump(stats, fh, ensure_ascii=False, indent=2)
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
