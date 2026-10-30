import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../account/account_widgets.dart';
import '../profile/profile_controller.dart';
import '../puzzle/application/puzzle_controller.dart';
import '../settings/settings_controller.dart';

/// FTUE (UX §5): splash with the arrow drawing itself (≤ 1 s) → optional
/// store-account sign-in + username, or a free-text name as a guest → the
/// tutorial puzzle. No permissions, no settings.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _splashDone = false;
  final _name = TextEditingController();
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    final animate = ref.read(uiTimersEnabledProvider);
    if (animate) {
      _splashTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _splashDone = true);
      });
    } else {
      _splashDone = true;
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start({required bool skipName}) async {
    final analytics = ref.read(analyticsProvider);
    if (!skipName && _name.text.trim().isNotEmpty) ref.read(profileProvider.notifier).setDisplayName(_name.text);
    analytics.track(AnalyticsEvents.onboardingStep, {'step': skipName ? 'name_skipped' : 'name_set'});
    ref.read(settingsProvider.notifier).completeOnboarding();
    final content = ref.read(puzzleContentProvider);
    final id = tutorialPuzzleIdFor(ref.read(settingsProvider).puzzleLang);
    final bundled = await content.isBundled(id);
    if (!mounted) return;
    if (bundled) {
      context.go('/play/$id');
    } else {
      ref.read(settingsProvider.notifier).completeTutorial();
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: reduceMotion ? 0 : 250),
          child: !_splashDone
              ? Center(key: const ValueKey('splash'), child: _ArrowSplash(animate: !reduceMotion))
              : Padding(
                  key: const ValueKey('name'),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(onPressed: () => _start(skipName: true), child: Text(l10n.skip)),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_forward_rounded, size: 72, color: theme.colorScheme.primary),
                      const SizedBox(height: 20),
                      Text(l10n.nameScreenTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(l10n.nameScreenBody, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 24),
                      // With Firebase on: the store account and a unique username instead of a free-text name.
                      if (ref.watch(accountServiceProvider).available) ...[
                        SignInButton(onSignedIn: () => _start(skipName: true)),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(l10n.playAsGuest, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                      TextField(
                        controller: _name,
                        maxLength: 24,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(hintText: l10n.defaultDisplayName, border: const OutlineInputBorder()),
                        onSubmitted: (_) => _start(skipName: false),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _start(skipName: false),
                          child: Text(l10n.letsGo),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// The brand arrow drawing itself.
class _ArrowSplash extends StatefulWidget {
  const _ArrowSplash({required this.animate});
  final bool animate;

  @override
  State<_ArrowSplash> createState() => _ArrowSplashState();
}

class _ArrowSplashState extends State<_ArrowSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: const Size(140, 80),
            painter: _ArrowPainter(progress: Curves.easeOut.transform(_c.value), color: color, rtl: rtl),
          ),
        ),
        const SizedBox(height: 12),
        Text(context.l10n.appTitle, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.progress, required this.color, required this.rtl});
  final double progress;
  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    final start = rtl ? size.width - 8 : 8.0;
    final end = rtl ? 8.0 : size.width - 8;
    final tipX = start + (end - start) * progress.clamp(0.0, 1.0);
    canvas.drawLine(Offset(start, y), Offset(tipX, y), paint);
    if (progress > 0.6) {
      final head = (progress - 0.6) / 0.4 * 26;
      final dir = rtl ? 1.0 : -1.0;
      canvas.drawLine(Offset(tipX, y), Offset(tipX + dir * head, y - head), paint);
      canvas.drawLine(Offset(tipX, y), Offset(tipX + dir * head, y + head), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.progress != progress || old.color != color;
}
