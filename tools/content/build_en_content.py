#!/usr/bin/env python3
"""Build the English lexicon and clue DB from public-domain / permissive sources.

Inputs (SRC_DIR):
  enable1.txt           ENABLE word list (public domain) – the answer inventory (no proper nouns)
  count_1w.txt          Norvig's unigram counts (word<TAB>count) – frequency ranks for difficulty
  dict/                 WordNet 3.0 database files (Princeton WordNet licence) – definitions and synonyms

Output (OUT_DIR): lexicon/words.jsonl.gz, clues/clues.jsonl.gz, stats.json

Usage: python3 -I build_en_content.py SRC_DIR OUT_DIR [--blocklist content/blocklist/en.txt]
"""
import argparse
import gzip
import hashlib
import json
import math
import os
import re
import sys
from collections import defaultdict

MIN_LEN, MAX_LEN = 2, 12
MAX_DEF_CHARS = 32
POS_FILES = {"n": "noun", "v": "verb", "a": "adj", "s": "adj", "r": "adv"}


def load_enable(path):
    words = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            w = line.strip().lower()
            if w and w.isalpha() and w.isascii() and MIN_LEN <= len(w) <= MAX_LEN:
                words.add(w)
    return words


def load_ranks(path):
    ranks = {}
    with open(path, encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            w = line.split("\t", 1)[0].strip().lower()
            if w and w not in ranks:
                ranks[w] = i + 1
    return ranks


def parse_wordnet(dict_dir):
    """Return synsets: offset+pos -> {words:[lemma...], gloss:str, pos, instance:bool}."""
    synsets = {}
    for pos in ("noun", "verb", "adj", "adv"):
        path = os.path.join(dict_dir, f"data.{pos}")
        with open(path, encoding="latin-1") as fh:
            for line in fh:
                if line.startswith("  "):
                    continue
                head, _, gloss = line.partition("|")
                parts = head.split()
                offset, ss_type = parts[0], parts[2]
                w_cnt = int(parts[3], 16)
                words = []
                idx = 4
                for _ in range(w_cnt):
                    lemma = parts[idx].lower()
                    lemma = re.sub(r"\(.*?\)$", "", lemma)  # adjective markers like (p)
                    words.append(lemma)
                    idx += 2
                p_cnt = int(parts[idx])
                instance = False
                hypernyms = []
                for k in range(p_cnt):
                    sym = parts[idx + 1 + k * 4]
                    target = parts[idx + 2 + k * 4]
                    if sym == "@i":
                        instance = True
                    if sym in ("@", "@i"):
                        hypernyms.append((target, pos))
                synsets[(offset, pos)] = {"words": words, "gloss": gloss.strip(), "pos": ss_type, "instance": instance, "hypernyms": hypernyms}
    return synsets


def definition_of(gloss):
    """Shortest leading clause of a WordNet gloss that still reads as a clue."""
    d = gloss.split(";")[0]
    d = re.sub(r"\"[^\"]*\"", "", d)           # drop examples
    d = re.sub(r"\([^)]*\)", "", d)             # drop parentheticals
    d = d.split(":")[0]
    d = re.sub(r"\s+", " ", d).strip(" ,.:;-")
    d = re.sub(r"^(a|an|the) ", "", d)
    if len(d) <= MAX_DEF_CHARS:
        return d
    # try the first comma clause, then a clause cut before a preposition
    first = d.split(",")[0].strip()
    if 2 <= len(first.split()) and len(first) <= MAX_DEF_CHARS:
        return first
    m = re.match(r"^(.{8,%d}?)\s(?:that|which|who|of|with|in|by|for|from|to|at|on|used|having|usually|often|especially)\b" % MAX_DEF_CHARS, d)
    if m and len(m.group(1).split()) >= 2:
        return m.group(1).strip(" ,")
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--blocklist", default=None)
    args = ap.parse_args()

    enable = load_enable(os.path.join(args.src_dir, "enable1.txt"))
    ranks = load_ranks(os.path.join(args.src_dir, "count_1w.txt"))
    synsets = parse_wordnet(os.path.join(args.src_dir, "dict"))
    blocked = set()
    if args.blocklist and os.path.exists(args.blocklist):
        with open(args.blocklist, encoding="utf-8") as fh:
            blocked = {l.strip().lower() for l in fh if l.strip() and not l.startswith("#")}

    # lemma -> list of (synset key, sense position)
    senses = defaultdict(list)
    for key, s in synsets.items():
        for pos_in_synset, lemma in enumerate(s["words"]):
            senses[lemma].append((key, pos_in_synset))

    words = {}
    clues = {}
    # percentile of the frequency rank among the answer inventory (0 = most common)
    ranked = sorted((ranks[w] for w in enable if w in ranks and w in senses))
    n_ranked = len(ranked) or 1
    import bisect

    def word_id(w):
        return "ew_" + hashlib.sha1(w.encode()).hexdigest()[:10]

    def clue_id(w, text):
        return "ec_" + hashlib.sha1(f"{w}|{text}".encode()).hexdigest()[:12]

    def freq_difficulty(w):
        r = ranks.get(w)
        if r is None:
            return 1.0
        pct = bisect.bisect_left(ranked, r) / n_ranked
        return min(1.0, 0.75 * pct + 0.25 * (math.log(r) / math.log(ranked[-1])))

    def add_clue(w, text, style, difficulty):
        text = text.strip()
        if not text or len(text) > MAX_DEF_CHARS:
            return
        if re.search(r"\b" + re.escape(w) + r"\b", text):
            return
        if not re.fullmatch(r"[A-Za-z0-9 ,'\-]+", text):
            return
        key = (w, text.lower())
        if key in clues:
            return
        clues[key] = {"id": clue_id(w, text.lower()), "wordId": word_id(w), "lang": "en", "text": text, "chars": len(text),
                      "style": style, "difficulty": round(min(1.0, difficulty), 3), "source": "wordnet", "status": "imported"}

    for w in sorted(enable):
        if w not in senses:
            continue  # no definition available → not usable as an answer
        n_senses = len(senses[w])
        fd = freq_difficulty(w)
        length_pen = min(1.0, max(0.0, (len(w) - 3) / 9.0))
        difficulty = round(min(1.0, 0.7 * fd + 0.3 * length_pen), 3)
        is_instance = all(synsets[k]["instance"] for k, _ in senses[w])
        words[w] = {"id": word_id(w), "lang": "en", "display": w.upper(), "canonical": w.upper(), "length": len(w),
                    "wordCount": 1, "clueCount": 0, "difficulty": difficulty, "freqRank": ranks.get(w),
                    "flags": {"multiword": False, "proper_noun": is_instance, "offensive": w in blocked},
                    "source": "enable+wordnet", "status": "imported"}
        for sense_no, (key, _pos_in_synset) in enumerate(senses[w]):
            s = synsets[key]
            sense_pen = min(0.3, sense_no * 0.08)      # later senses are more obscure
            d = definition_of(s["gloss"])
            if d and sense_no < 3:
                add_clue(w, d, "definition", 0.35 + 0.4 * fd + sense_pen)
            if sense_no >= 2:
                continue  # synonyms of rare senses mislead (cat = "guy")
            # category clue from the hypernym ("feline" for cat)
            for hkey in s["hypernyms"][:1]:
                h = synsets.get(hkey)
                if not h:
                    continue
                for hl in h["words"]:
                    if hl == w or "_" in hl or not hl.isalpha() or hl not in enable or ranks.get(hl, 10**9) > 40000:
                        continue
                    add_clue(w, hl, "hypernym", 0.4 + 0.35 * fd + sense_pen)
                    break
            for syn in s["words"]:
                if syn == w or "_" in syn or not syn.isalpha() or syn not in enable:
                    continue
                if ranks.get(syn, 10**9) > 60000:
                    continue
                syn_fd = freq_difficulty(syn)
                add_clue(w, syn, "synonym", 0.25 + 0.3 * fd + 0.3 * syn_fd + sense_pen)

    # drop words without any clue
    counts = defaultdict(int)
    for (w, _), c in clues.items():
        counts[w] += 1
    words = {w: j for w, j in words.items() if counts.get(w, 0) > 0}
    for w, j in words.items():
        j["clueCount"] = counts[w]

    os.makedirs(os.path.join(args.out_dir, "lexicon"), exist_ok=True)
    os.makedirs(os.path.join(args.out_dir, "clues"), exist_ok=True)
    with gzip.open(os.path.join(args.out_dir, "lexicon", "words.jsonl.gz"), "wt", encoding="utf-8") as fh:
        for w in sorted(words):
            fh.write(json.dumps(words[w]) + "\n")
    with gzip.open(os.path.join(args.out_dir, "clues", "clues.jsonl.gz"), "wt", encoding="utf-8") as fh:
        for key in sorted(clues):
            if key[0] in words:
                fh.write(json.dumps(clues[key]) + "\n")
    stats = {
        "enableWords": len(enable), "wordsWithClues": len(words), "clues": sum(1 for k in clues if k[0] in words),
        "wordsByLength": {str(n): sum(1 for j in words.values() if j["length"] == n) for n in range(MIN_LEN, MAX_LEN + 1)},
        "blocked": sum(1 for j in words.values() if j["flags"]["offensive"]),
        "difficultyHistogram": {str(b / 10): sum(1 for j in words.values() if round(j["difficulty"], 1) == b / 10) for b in range(0, 11)},
    }
    with open(os.path.join(args.out_dir, "stats.json"), "w", encoding="utf-8") as fh:
        json.dump(stats, fh, indent=2)
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    sys.exit(main())
