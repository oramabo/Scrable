import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// 0–3 stars, never colour-only (empty stars are outlined).
class StarsRow extends StatelessWidget {
  const StarsRow({super.key, required this.stars, this.size = 20, this.total = 3});

  final int stars;
  final double size;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.completionStars,
      value: '$stars/$total',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++)
              Icon(
                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: i < stars ? const Color(0xFFE0A526) : scheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}

class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.balance, this.onTap, this.compact = false});

  final int balance;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final child = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded, size: 20, color: Color(0xFFE0A526)),
          const SizedBox(width: 6),
          Text('$balance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Semantics(
      label: l10n.coins,
      value: l10n.coinsBalance(balance),
      button: onTap != null,
      child: ExcludeSemantics(
        child: onTap == null
            ? child
            : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A tappable card with a leading icon, title, subtitle and optional trailing.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
    this.semanticsLabel,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Shows a one-line floating toast, replacing any current one. Colours are
/// set explicitly (inverse surface + its "on" colour) so the toast never
/// inherits a transparent background or an unreadable text colour from an
/// ancestor theme — the login-bonus toast used to render as an empty bar.
void showSnack(BuildContext context, String message, {Duration duration = const Duration(seconds: 3), IconData? icon}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  final style = Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onInverseSurface);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      duration: duration,
      content: Row(
        children: [
          if (icon != null) ...[Icon(icon, color: scheme.onInverseSurface, size: 20), const SizedBox(width: 10)],
          Expanded(child: Text(message, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ));
}

/// Flies a few coin icons from [from] to [to] (global coordinates) in an
/// overlay and resolves when they have landed. Reduced motion skips it.
Future<void> flyCoins(BuildContext context, {required Offset from, required Offset to, required int coins}) async {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (reduceMotion) return;
  final count = coins >= 100 ? 8 : (coins >= 40 ? 6 : 4);
  final entry = OverlayEntry(builder: (_) => FlyingCoins(from: from, to: to, count: count));
  overlay.insert(entry);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  entry.remove();
}

/// Centre of a widget identified by [key] in global coordinates, or null.
Offset? centerOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(box.size.center(Offset.zero));
}

/// Coins flying towards the counter (UX §4 "coins fly to the counter").
class FlyingCoins extends StatefulWidget {
  const FlyingCoins({super.key, required this.from, required this.to, required this.count});
  final Offset from;
  final Offset to;
  final int count;

  @override
  State<FlyingCoins> createState() => _FlyingCoinsState();
}

class _FlyingCoinsState extends State<FlyingCoins> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          children: [
            for (var i = 0; i < widget.count; i++)
              Builder(builder: (_) {
                final delay = i / widget.count * 0.4;
                final t = Curves.easeInOut.transform(((_c.value - delay) / (1 - delay)).clamp(0.0, 1.0));
                final spread = Offset((i - widget.count / 2) * 18.0, -40.0 * math.sin(t * math.pi));
                final pos = Offset.lerp(widget.from, widget.to, t)! + spread * (1 - t);
                return Positioned(
                  left: pos.dx - 12,
                  top: pos.dy - 12,
                  child: Opacity(
                    opacity: t < 0.95 ? 1 : (1 - (t - 0.95) / 0.05),
                    child: const Icon(Icons.monetization_on_rounded, size: 24, color: Color(0xFFE0B64A)),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
