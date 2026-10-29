import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/util/clock.dart';
import '../../../../core/widgets/common.dart';
import '../../application/puzzle_session.dart';

enum CompletionAction { next, home, leaderboard, daily }

Future<CompletionAction?> showCompletionSheet(
  BuildContext context, {
  required PuzzleSession session,
  required CompletionSummary summary,
  required bool hasNext,
  required String title,
  VoidCallback? onShared,
  bool showLeaderboard = false,
}) {
  return showModalBottomSheet<CompletionAction>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (_) => CompletionSheet(
      session: session,
      summary: summary,
      hasNext: hasNext,
      title: title,
      onShared: onShared,
      showLeaderboard: showLeaderboard,
    ),
  );
}

class CompletionSheet extends StatefulWidget {
  const CompletionSheet({
    super.key,
    required this.session,
    required this.summary,
    required this.hasNext,
    required this.title,
    this.onShared,
    this.showLeaderboard = false,
  });

  final PuzzleSession session;
  final CompletionSummary summary;
  final bool hasNext;
  final String title;

  /// Called after the share sheet was opened (records the game event).
  final VoidCallback? onShared;
  final bool showLeaderboard;

  @override
  State<CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<CompletionSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (_reduceMotion) {
        _confetti.value = 0.55;
      } else {
        _confetti.forward();
      }
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  String _starsText(int stars) => List.filled(stars, '⭐').join();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = widget.summary;
    final time = formatDuration(s.elapsedMs);

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confetti,
                builder: (context, _) => CustomPaint(
                  painter: _ConfettiPainter(progress: _confetti.value, color: theme.colorScheme.primary, static: _reduceMotion),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    s.isDaily ? l10n.completionDailyTitle : l10n.completionTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                Text(widget.title, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
                Center(child: StarsRow(stars: s.stars, size: 44)),
                if (s.perfect)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.completionPerfect,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Stat(icon: Icons.timer_outlined, label: l10n.completionTime, value: time),
                    _Stat(icon: Icons.lightbulb_outline_rounded, label: l10n.completionHints, value: '${s.hintsUsed}'),
                    _Stat(
                      icon: Icons.monetization_on_rounded,
                      label: l10n.coins,
                      value: l10n.completionCoins(s.coinsEarned),
                      iconColor: const Color(0xFFE0A526),
                    ),
                  ],
                ),
                if (s.streak != null && s.streak! > 0) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Chip(
                      avatar: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFE0652A)),
                      label: Text(l10n.streakDays(s.streak!)),
                    ),
                  ),
                ],
                if (s.learned.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(l10n.wordsLearned, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Directionality(
                    textDirection: puzzleTextDirection(widget.session.lang),
                    child: Column(
                      children: [
                        for (final w in s.learned)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(w.answer, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            subtitle: Text(w.clue),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (s.firstCompletion)
                  Card(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    child: ListTile(
                      leading: Icon(Icons.celebration_rounded, color: theme.colorScheme.primary),
                      title: Text(l10n.firstCompletionTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      subtitle: Text(l10n.firstCompletionBody(s.firstCompletionBonus)),
                    ),
                  ),
                if (s.firstCompletion) const SizedBox(height: 10),
                // Exactly one primary action (UX §4).
                if (s.firstCompletion)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(CompletionAction.daily),
                    icon: const Icon(Icons.today_rounded),
                    label: Text(l10n.toDaily),
                  )
                else if (widget.hasNext)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(CompletionAction.next),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(l10n.nextPuzzle),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(CompletionAction.home),
                    icon: const Icon(Icons.home_rounded),
                    label: Text(l10n.backHome),
                  ),
                if (widget.showLeaderboard) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(CompletionAction.leaderboard),
                    icon: const Icon(Icons.leaderboard_rounded),
                    label: Text(l10n.leaderboardTitle),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final text = l10n.shareText(widget.title, time, _starsText(s.stars));
                          SharePlus.instance.share(ShareParams(text: text)).ignore();
                          widget.onShared?.call();
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: Text(l10n.share),
                      ),
                    ),
                    if (widget.hasNext || s.firstCompletion) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(CompletionAction.home),
                          icon: const Icon(Icons.home_rounded),
                          label: Text(l10n.backHome),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, this.iconColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      value: value,
      child: ExcludeSemantics(
        child: Column(
          children: [
            Icon(icon, color: iconColor ?? theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Simple confetti: deterministic particles falling with a fade. With
/// reduced motion, a static scattering is drawn instead.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.color, required this.static});

  final double progress;
  final Color color;
  final bool static;

  static const _palette = [Color(0xFFE0A526), Color(0xFF2F6F6D), Color(0xFFB5471F), Color(0xFF7A9E7E), Color(0xFF5B6FB8)];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rng = math.Random(7);
    final paint = Paint();
    final fade = static ? 0.6 : (1 - progress).clamp(0.0, 1.0);
    for (var i = 0; i < 70; i++) {
      final x0 = rng.nextDouble() * size.width;
      final speed = 0.6 + rng.nextDouble();
      final y = static ? rng.nextDouble() * size.height * 0.5 : (progress * speed * size.height * 1.2 - 20) % (size.height + 40) - 20;
      final drift = math.sin(progress * 6 + i) * 12;
      final w = 5 + rng.nextDouble() * 5;
      paint.color = _palette[i % _palette.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x0 + drift, y);
      canvas.rotate(static ? i.toDouble() : progress * 8 + i);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.progress != progress;
}
