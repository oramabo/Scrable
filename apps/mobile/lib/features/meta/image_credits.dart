import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Attribution for a picture clue the player has seen.
class ImageCredit {
  const ImageCredit({required this.id, required this.puzzleId, required this.src, this.credit, this.license, this.sourceUrl, this.wordId});

  final String id;
  final String puzzleId;
  final String src;
  final String? credit;
  final String? license;
  final String? sourceUrl;
  final String? wordId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'puzzleId': puzzleId,
        'src': src,
        if (credit != null) 'credit': credit,
        if (license != null) 'license': license,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (wordId != null) 'wordId': wordId,
      };

  static ImageCredit fromJson(Map<String, dynamic> j) => ImageCredit(
        id: j['id'] as String,
        puzzleId: (j['puzzleId'] as String?) ?? '',
        src: (j['src'] as String?) ?? '',
        credit: j['credit'] as String?,
        license: j['license'] as String?,
        sourceUrl: j['sourceUrl'] as String?,
        wordId: j['wordId'] as String?,
      );
}

/// Collects picture credits from puzzles as they load (About → image credits).
class ImageCreditsController extends Notifier<List<ImageCredit>> {
  static const _key = 'meta/image_credits';

  @override
  List<ImageCredit> build() {
    ref.read(jsonStoreProvider).read(_key).then((j) {
      final rows = j?['credits'];
      if (rows is List) {
        state = [for (final r in rows) ImageCredit.fromJson(r as Map<String, dynamic>)];
      }
    }).ignore();
    return const [];
  }

  /// Adds every picture clue of [puzzle] that is not known yet.
  void addFromPuzzle(Puzzle puzzle) {
    final known = state.map((c) => c.id).toSet();
    final added = <ImageCredit>[];
    for (final cell in puzzle.clueCells) {
      for (final slot in cell.slots) {
        final img = slot.image;
        if (img == null || known.contains(img.id)) continue;
        known.add(img.id);
        added.add(ImageCredit(
          id: img.id,
          puzzleId: puzzle.id,
          src: img.src,
          credit: img.credit,
          license: img.license,
          sourceUrl: img.sourceUrl,
          wordId: slot.wordId,
        ));
      }
    }
    if (added.isEmpty) return;
    state = [...state, ...added];
    ref.read(jsonStoreProvider).write(_key, {'credits': state.map((c) => c.toJson()).toList()}).ignore();
  }

  void clear() => state = const [];
}

final imageCreditsProvider = NotifierProvider<ImageCreditsController, List<ImageCredit>>(ImageCreditsController.new);
