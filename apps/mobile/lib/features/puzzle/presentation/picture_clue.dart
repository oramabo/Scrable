import 'dart:typed_data';

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';

/// Bytes of a picture clue (bundled → cache → CDN), null when unavailable.
final clueImageBytesProvider = FutureProvider.family<Uint8List?, (String, String)>(
  (ref, key) => ref.watch(clueImageStoreProvider(key.$1)).bytes(key.$1, key.$2),
);

/// A picture clue rendered large (clue bar, clue-cell popover). Falls back to
/// an icon placeholder while loading or when the image is missing.
class PictureClueImage extends ConsumerWidget {
  const PictureClueImage({super.key, required this.lang, required this.image, this.height = 72});

  final String lang;
  final ClueImage image;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final bytes = ref.watch(clueImageBytesProvider((lang, image.src))).value;
    final aspect = (image.width != null && image.height != null && image.height! > 0) ? image.width! / image.height! : 1.0;
    final width = (height * aspect).clamp(height * 0.6, height * 1.6);
    return Semantics(
      label: '${l10n.pictureClue}${image.credit == null ? '' : ' · ${image.credit}'}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: height,
          width: width,
          child: bytes == null
              ? Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                )
              : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }
}
