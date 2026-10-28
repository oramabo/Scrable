#!/usr/bin/env python3
"""Turn the scraped Mordo feed pages into the Hebrew clue DB and lexicon used by the generator.

Input : RAW_DIR/pages/page_NNNN.json (written by scrape_mordo.py)
Output: OUT_DIR/clues/clues.jsonl.gz, OUT_DIR/lexicon/words.jsonl.gz, OUT_DIR/stats.json

Every answer listed under a definition becomes a (clue, word) pair. Words are keyed by their normalised
form (final letters folded to base letters, geresh kept and fused, punctuation and spaces dropped) so
"ים המלח" and "ים-המלח" are one word with several display forms.

Usage: python3 -I build_he_content.py RAW_DIR OUT_DIR
"""
import glob
import gzip
import hashlib
import html
import json
import math
import os
import re
import sys
import unicodedata
from collections import defaultdict

HEBREW_LETTERS = "אבגדהוזחטיכלמנסעפצקרשת"
FINAL_TO_BASE = {"ך": "כ", "ם": "מ", "ן": "נ", "ף": "פ", "ץ": "צ"}
GERESH_CHARS = "׳'’´ʼ"
GERSHAYIM_CHARS = "״\""
GERESH_LETTERS = set("גזצתד")  # letters that take a geresh in loanwords (ג'ינס, ז'קט, צ'יפס, ת'ינק, ד'ו)

PROPER_HINTS = re.compile(
    r"(שחקן|שחקנית|זמר|זמרת|סופר|סופרת|משורר|משוררת|במאי|במאית|מלחין|מלחינה|צייר|ציירת|פסל|פסלת|שדרן|שדרנית|מגיש|מגישה|"
    r"עיר |עיר$|כפר|יישוב|ישוב|קיבוץ|מושב|מדינה|נהר|הר |^אי |^איים|אגם|בירת|נמל|מחוז|חבל ארץ|מערי|מנהרות|מהרי|מאיי|מאגמי|"
    r"שם פרטי|שם משפחה|שם של|כינויו|כינויה|דמות|גיבור|נשיא|ראש הממשלה|ראש ממשלה|שר |שרת |מלך|מלכת|קיסר|נביא|נביאה|"
    r"כדורגלן|כדורסלן|שחיין|שחיינית|אצן|אצנית|אתלט|ספורטאי|ספורטאית|מאמן|מאמנת|שופט|שופטת|חברת|מותג|להקה|להקת|סרט|סדרה|ספר של|רומן|אלבום|שיר של|"
    r"פילוסוף|מדען|מדענית|פיזיקאי|כימאי|ממציא|רופא|מנהיג|מצביא|גנרל|פוליטיקאי|חבר כנסת|ח\"כ|עיתונאי|עיתונאית|דוגמנית|דוגמן|אסטרונום|אסטרונאוט|היסטוריון|"
    r"גיטריסט|מתופף|פסנתרן|כנר|מנצח|רקדן|רקדנית|אמן |אמנית|צלם|צלמת|קריקטוריסט|אנימטור|"
    r"מספר ד?גול|נבחרת|מועדון|קבוצת|חבר להקת|מנכ\"ל|יזם|איל הון|אדריכל|מעצב|מעצבת|שפית|שף |קומיקאי|בדרן|בדרנית|"
    r"ישראלי|ישראלית|אמריקאי|אמריקאית|אנגלי|אנגלית|בריטי|בריטית|צרפתי|צרפתייה|גרמני|גרמנייה|רוסי|רוסייה|איטלקי|איטלקייה|ספרדי|ספרדייה|"
    r"יפני|יפנית|סיני|סינית|קוריאני|הודי|הודית|מצרי|מצרית|טורקי|יווני|פולני|הולנדי|שוודי|נורווגי|דני|קנדי|אוסטרלי|ברזילאי|ארגנטינאי|מקסיקני|"
    r"בעבר$|לשעבר)")

TITLE_SUFFIXES = re.compile(r"\s*(תשחץ|תשבץ|מילון|פתרון|הגדרה)\s*$")
MARKER = re.compile(r"פתרון\s+(?:(\d+)\s+אותיות(?:\s+ומעלה)?|(?:של\s+)?שתי\s+מילים\s+ומעלה)\s*:", re.U)
TAG = re.compile(r"<[^>]+>")
BOLD = re.compile(r"<b[^>]*>(.*?)</b>", re.S)


def strip_niqqud(s: str) -> str:
    return "".join(ch for ch in s if not (0x0591 <= ord(ch) <= 0x05C7))


def normalise(answer: str):
    """Return (canonical display, normalised key, symbol count, word count) or None when not a Hebrew answer."""
    s = strip_niqqud(html.unescape(answer)).replace("\xa0", " ").strip()
    s = re.sub(r"\s*[\(\[].*$", "", s)  # drop trailing explanations such as "כושר ( מסוגלות )"
    s = re.sub(r"\s+", " ", s)
    s = s.strip(" .,;:!?()[]{}")
    if not s:
        return None
    key = []
    display = []
    word_count = 1 if s else 0
    prev_letter = False
    for ch in s:
        if ch in HEBREW_LETTERS:
            base = ch
            key.append(base)
            display.append(ch)
            prev_letter = True
        elif ch in FINAL_TO_BASE:
            key.append(FINAL_TO_BASE[ch])
            display.append(ch)
            prev_letter = True
        elif ch in GERESH_CHARS:
            if prev_letter and key and key[-1] in GERESH_LETTERS and not key[-1].endswith("׳"):
                key[-1] = key[-1] + "׳"
                display.append("׳")
            prev_letter = False
        elif ch in GERSHAYIM_CHARS:
            display.append("״")
            prev_letter = False
        elif ch in " -־":
            if display and display[-1] not in " -":
                display.append("-" if ch in "-־" else " ")
                if ch == " ":
                    word_count += 1
                else:
                    word_count += 1
            prev_letter = False
        else:
            return None  # Latin letters, digits, unexpected punctuation
    while display and display[-1] in " -":
        display.pop()
    if not key or len(key) < 2 or len(key) > 14:
        return None
    return "".join(display), "".join(key), len(key), max(1, word_count)


def clean_title(title: str) -> list:
    """The title is 'short clue | long clue תשבץ'. Return distinct clue variants, longest first."""
    parts = [p.strip() for p in html.unescape(title).split("|")]
    out = []
    for p in parts:
        p = strip_niqqud(p)
        prev = None
        while prev != p:
            prev = p
            p = TITLE_SUFFIXES.sub("", p).strip(" -:,")
        if p and p not in out:
            out.append(p)
    out.sort(key=len, reverse=True)
    return out


def parse_answers(content: str):
    """Yield (declared_group, answer_text) from the post body."""
    body = html.unescape(content)
    i = body.find("בהצלחה")
    if i >= 0:
        body = body[i:]
    j = body.find("ביטויים דומים")
    if j >= 0:
        body = body[:j]
    positions = [(m.start(), m.end(), m.group(1)) for m in MARKER.finditer(body)]
    for idx, (start, end, group) in enumerate(positions):
        seg_end = positions[idx + 1][0] if idx + 1 < len(positions) else len(body)
        segment = body[end:seg_end]
        bolds = BOLD.findall(segment)
        text = " ".join(TAG.sub(" ", b) for b in bolds) if bolds else TAG.sub(" ", segment)
        text = text.replace("\xa0", " ")
        for raw in re.split(r"[,\n]+", text):
            raw = raw.strip()
            if raw:
                yield (group or "multi"), raw


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    raw_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out_dir, "clues"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "lexicon"), exist_ok=True)

    words = {}            # key -> dict
    pairs = {}            # (key, clue) -> dict
    posts = 0
    posts_with_answers = 0
    rejected_answers = 0
    for path in sorted(glob.glob(os.path.join(raw_dir, "pages", "page_*.json"))):
        with open(path, encoding="utf-8") as fh:
            page = json.load(fh)
        for entry in page["entries"]:
            posts += 1
            clues = clean_title(entry.get("title") or "")
            if not clues:
                continue
            found = False
            for group, raw in parse_answers(entry.get("content") or ""):
                norm = normalise(raw)
                if norm is None:
                    rejected_answers += 1
                    continue
                display, key, length, word_count = norm
                found = True
                w = words.get(key)
                if w is None:
                    w = words[key] = {"key": key, "displays": {}, "length": length, "wordCount": word_count, "clueKeys": set()}
                w["displays"][display] = w["displays"].get(display, 0) + 1
                w["wordCount"] = min(w["wordCount"], word_count) if word_count > 1 else 1 if w["wordCount"] == 1 else w["wordCount"]
                for clue in clues:
                    if len(clue) > 60:
                        continue
                    w["clueKeys"].add(clue)
                    p = pairs.get((key, clue))
                    if p is None:
                        pairs[(key, clue)] = {"key": key, "clue": clue, "url": entry.get("url"), "published": (entry.get("published") or "")[:10]}
            if found:
                posts_with_answers += 1

    # difficulty: words that answer many clues are common crossword fodder → easier.
    # Use the percentile rank of the clue count (ties share the average rank) so the
    # scale is stable whatever the corpus size.
    counts = sorted(len(w["clueKeys"]) for w in words.values())
    n_words = len(counts) or 1
    first_index = {}
    for i, c in enumerate(counts):
        first_index.setdefault(c, i)
    last_index = {}
    for i, c in enumerate(counts):
        last_index[c] = i
    pct_of_count = {c: (first_index[c] + last_index[c]) / 2 / max(1, n_words - 1) for c in first_index}
    max_log = math.log1p(counts[-1]) if counts else 1.0

    def freq_score(n_clues: int) -> float:
        # 0 = very common, 1 = rare; blend percentile with log count so the top words spread out
        return 0.7 * (1.0 - pct_of_count.get(n_clues, 0.5)) + 0.3 * (1.0 - math.log1p(n_clues) / max_log)

    def word_id(key: str) -> str:
        return "hw_" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:10]

    def clue_id(key: str, clue: str) -> str:
        return "hc_" + hashlib.sha1((key + "|" + clue).encode("utf-8")).hexdigest()[:12]

    with gzip.open(os.path.join(out_dir, "lexicon", "words.jsonl.gz"), "wt", encoding="utf-8") as fh:
        for key in sorted(words):
            w = words[key]
            display = max(w["displays"].items(), key=lambda kv: (kv[1], -len(kv[0])))[0]
            n_clues = len(w["clueKeys"])
            proper_hits = sum(1 for c in w["clueKeys"] if PROPER_HINTS.search(c))
            # a third of the clues (or any clue when there are at most two) pointing at a person/place marks a proper noun
            is_proper = proper_hits > 0 and (proper_hits * 3 >= n_clues or n_clues <= 2)
            length_pen = min(1.0, max(0.0, (w["length"] - 3) / 9.0))
            has_geresh = "׳" in key
            difficulty = round(min(1.0, 0.6 * freq_score(n_clues) + 0.25 * length_pen + (0.1 if w["wordCount"] > 1 else 0.0) + (0.05 if has_geresh else 0.0)), 3)
            fh.write(json.dumps({
                "id": word_id(key), "lang": "he", "display": display, "canonical": key, "length": w["length"],
                "wordCount": w["wordCount"], "clueCount": n_clues, "difficulty": difficulty,
                "flags": {"multiword": w["wordCount"] > 1, "geresh": has_geresh, "proper_noun": is_proper},
                "source": "mordo", "status": "imported",
            }, ensure_ascii=False) + "\n")

    with gzip.open(os.path.join(out_dir, "clues", "clues.jsonl.gz"), "wt", encoding="utf-8") as fh:
        for (key, clue) in sorted(pairs):
            p = pairs[(key, clue)]
            w = words[key]
            n_clues = len(w["clueKeys"])
            # a clue shared by many words is vaguer → harder; long clues are harder to fit
            vague = min(1.0, (len(clue) > 25) * 0.2)
            fh.write(json.dumps({
                "id": clue_id(key, clue), "wordId": word_id(key), "lang": "he", "text": clue, "chars": len(clue),
                "style": "definition", "difficulty": round(min(1.0, 0.5 * freq_score(n_clues) + 0.25 + vague), 3),
                "source": "mordo", "sourceUrl": p["url"], "status": "imported",
            }, ensure_ascii=False) + "\n")

    stats = {
        "posts": posts, "postsWithAnswers": posts_with_answers, "rejectedAnswers": rejected_answers,
        "words": len(words), "pairs": len(pairs),
        "wordsByLength": {str(n): sum(1 for w in words.values() if w["length"] == n) for n in range(2, 15)},
        "multiword": sum(1 for w in words.values() if w["wordCount"] > 1),
        "properNouns": sum(1 for w in words.values() if (lambda h, n: h > 0 and (h * 3 >= n or n <= 2))(sum(1 for c in w["clueKeys"] if PROPER_HINTS.search(c)), len(w["clueKeys"]))),
    }
    with open(os.path.join(out_dir, "stats.json"), "w", encoding="utf-8") as fh:
        json.dump(stats, fh, ensure_ascii=False, indent=2)
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
