import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../puzzle/application/puzzle_controller.dart';
import '../settings/settings_controller.dart';

/// Three short screens, then the tutorial puzzle (first puzzle of he-l1-p01).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool tutorial}) async {
    ref.read(analyticsProvider).track(AnalyticsEvents.onboardingStep, {'step': tutorial ? 'tutorial' : 'skip'});
    ref.read(settingsProvider.notifier).completeOnboarding();
    if (!tutorial) {
      ref.read(settingsProvider.notifier).completeTutorial();
      if (mounted) context.go('/');
      return;
    }
    final content = ref.read(puzzleContentProvider);
    final id = tutorialPuzzleIdFor(ref.read(settingsProvider).puzzleLang);
    final bundled = await content.isBundled(id);
    if (!mounted) return;
    if (bundled) {
      context.go('/play/$id');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pages = [
      (Icons.grid_on_rounded, l10n.onboarding1Title, l10n.onboarding1Body),
      (Icons.touch_app_outlined, l10n.onboarding2Title, l10n.onboarding2Body),
      (Icons.monetization_on_outlined, l10n.onboarding3Title, l10n.onboarding3Body),
    ];
    final last = _page == pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: () => _finish(tutorial: false), child: Text(l10n.skip)),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  ref.read(analyticsProvider).track(AnalyticsEvents.onboardingStep, {'step': i + 1});
                },
                itemBuilder: (context, i) {
                  final (icon, title, body) = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(36),
                          ),
                          child: Icon(icon, size: 64, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(height: 32),
                        Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (last) {
                      _finish(tutorial: true);
                    } else {
                      _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                    }
                  },
                  child: Text(last ? l10n.startTutorial : l10n.next),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
