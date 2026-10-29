import 'dart:convert';

import '../lang/language_profile.dart';
import '../model/puzzle.dart';

/// A word usable as an answer.
class LexWord {
  LexWord({
    required this.id,
    required this.display,
    required this.canonical,
    required this.symbols,
    this.wordCount = 1,
    this.difficulty = 0.5,
    this.clueCount = 0,
    this.isProper = false,
    this.isMultiword = false,
    this.hasVariant = false,
    this.blocked = false,
    this.status = 'approved',
    this.lemmaId,
  });

  final String id;
  final String display;
  final String canonical;
  final List<int> symbols;
  final int wordCount;
  final double difficulty;
  final int clueCount;
  final bool isProper;
  final bool isMultiword;
  final bool hasVariant;
  final bool blocked;
  final String status;

  /// Lemma/root id to avoid two forms of the same word in a puzzle; defaults
  /// to the word id.
  final String? lemmaId;

  int get length => symbols.length;
  String get lemma => lemmaId ?? id;

  /// Clues attached by [Lexicon.attachClues].
  final List<LexClue> clues = [];

  /// Picture available for this word (picture clues), attached by [Lexicon.attachImages].
  ClueImage? image;

  /// Index into the dictionary (set by DictionaryIndex).
  int dictIndex = -1;
}

class LexClue {
  const LexClue({
    required this.id,
    required this.wordId,
    required this.text,
    this.style = 'definition',
    this.difficulty = 0.5,
    this.minLevel = 1,
    this.maxLevel = 6,
    this.status = 'approved',
    this.lastDailyUse = const {},
  });

  final String id;
  final String wordId;
  final String text;
  final String style;
  final double difficulty;
  final int minLevel;
  final int maxLevel;
  final String status;

  /// variant -> ISO date of last use in a daily puzzle.
  final Map<String, String> lastDailyUse;
}

/// All words and clues of one language.
class Lexicon {
  Lexicon(this.lang, {required List<LexWord> words, required List<LexClue> clues, this.snapshotId = 'dev'})
      : words = List.unmodifiable(words),
        clues = List.unmodifiable(clues),
        wordById = {for (final w in words) w.id: w},
        clueById = {for (final c in clues) c.id: c} {
    _attachClues();
  }

  final LanguageProfile lang;
  final List<LexWord> words;
  final List<LexClue> clues;
  final Map<String, LexWord> wordById;
  final Map<String, LexClue> clueById;
  final String snapshotId;

  void _attachClues() {
    for (final c in clues) {
      wordById[c.wordId]?.clues.add(c);
    }
  }

  /// Attaches pictures from `images.jsonl` records ({wordId, file, license,
  /// credit, sourceUrl, width, height}). Returns how many words got a picture.
  int attachImages(Iterable<String> imageLines) {
    var n = 0;
    for (final line in imageLines) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      final w = wordById[j['wordId'] as String];
      if (w == null) continue;
      w.image = ClueImage(
        id: 'img_${w.id}',
        src: j['file'] as String,
        width: j['width'] as int?,
        height: j['height'] as int?,
        credit: (j['credit'] as String?)?.isEmpty ?? true ? null : j['credit'] as String,
        license: j['license'] as String?,
        sourceUrl: j['sourceUrl'] as String?,
      );
      n++;
    }
    return n;
  }

  int get imageCount => words.where((w) => w.image != null).length;

  /// Parses JSONL exports (one JSON object per line) produced by the content
  /// tools. Lines that are not valid for the language are skipped.
  static Lexicon fromJsonl(LanguageProfile lang, {required Iterable<String> wordLines, required Iterable<String> clueLines, String snapshotId = 'dev'}) {
    final words = <LexWord>[];
    for (final line in wordLines) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      if ((j['lang'] as String?) != null && j['lang'] != lang.code) continue;
      final symbols = lang.normalize((j['canonical'] ?? j['display']) as String);
      if (symbols == null) continue;
      final flags = (j['flags'] as Map?) ?? const {};
      words.add(LexWord(
        id: j['id'] as String,
        display: j['display'] as String,
        canonical: lang.canonicalKey(symbols),
        symbols: symbols,
        wordCount: (j['wordCount'] as int?) ?? 1,
        difficulty: ((j['difficulty'] as num?) ?? 0.5).toDouble(),
        clueCount: (j['clueCount'] as int?) ?? 0,
        isProper: (flags['proper_noun'] as bool?) ?? (flags['proper'] as bool?) ?? false,
        isMultiword: (flags['multiword'] as bool?) ?? ((j['wordCount'] as int?) ?? 1) > 1,
        hasVariant: (flags['geresh'] as bool?) ?? symbols.any(lang.isVariantSymbol),
        blocked: (flags['offensive'] as bool?) ?? false,
        status: (j['status'] as String?) ?? 'approved',
        lemmaId: j['lemmaId'] as String?,
      ));
    }
    final clues = <LexClue>[];
    for (final line in clueLines) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      if ((j['lang'] as String?) != null && j['lang'] != lang.code) continue;
      final usage = (j['usage'] as Map?)?['lastDaily'] as Map?;
      clues.add(LexClue(
        id: j['id'] as String,
        wordId: j['wordId'] as String,
        text: (j['text'] as String).trim(),
        style: (j['style'] as String?) ?? 'definition',
        difficulty: ((j['difficulty'] as num?) ?? 0.5).toDouble(),
        minLevel: (j['minLevel'] as int?) ?? 1,
        maxLevel: (j['maxLevel'] as int?) ?? 6,
        status: (j['status'] as String?) ?? 'approved',
        lastDailyUse: usage == null ? const {} : usage.map((k, v) => MapEntry(k as String, v as String)),
      ));
    }
    return Lexicon(lang, words: words, clues: clues, snapshotId: snapshotId);
  }
}
