import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/daily/daily_screen.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/packs/packs_screens.dart';
import '../features/puzzle/presentation/puzzle_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/store/store_screen.dart';

/// Route paths.
abstract final class Routes {
  static const home = '/';
  static const packs = '/packs';
  static const daily = '/daily';
  static const settings = '/settings';
  static const onboarding = '/onboarding';
  static const store = '/store';
  static const stats = '/stats';
  static const about = '/about';
  static String level(int level) => '/levels/$level';
  static String pack(String id) => '/pack/$id';
  static String play(String puzzleId) => '/play/$puzzleId';
}

GoRouter buildRouter(Ref ref, {String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      if (!done && state.matchedLocation != Routes.onboarding) return Routes.onboarding;
      return null;
    },
    routes: [
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeTab())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.packs, builder: (_, _) => const LevelsTab())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.daily, builder: (_, _) => const DailyTab())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsTab())]),
        ],
      ),
      GoRoute(
        path: '/levels/:level',
        builder: (_, state) => PacksOfLevelScreen(level: int.tryParse(state.pathParameters['level'] ?? '') ?? 1),
      ),
      GoRoute(path: '/pack/:packId', builder: (_, state) => PackScreen(packId: state.pathParameters['packId']!)),
      GoRoute(path: '/play/:puzzleId', builder: (_, state) => PuzzleScreen(puzzleId: state.pathParameters['puzzleId']!)),
      GoRoute(path: Routes.store, builder: (_, _) => const StoreScreen()),
      GoRoute(path: Routes.stats, builder: (_, _) => const StatsScreen()),
      GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});
