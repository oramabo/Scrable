import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/daily/daily_screen.dart';
import '../features/home/home_shell.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/meta/achievements_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/packs/packs_screens.dart';
import '../features/profile/profile_screen.dart';
import '../features/puzzle/presentation/puzzle_screen.dart';
import '../features/season/season_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/theme/theme_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/store/store_screen.dart';
import '../features/together/coop_screens.dart';
import '../features/together/together_screen.dart';
import '../features/together/versus_screens.dart';

/// Route paths. Tabs (UX §3): Play · Daily · Together · Me.
abstract final class Routes {
  static const home = '/';
  static const daily = '/daily';
  static const together = '/together';
  static const me = '/me';
  static const settings = '/settings';
  static const levels = '/levels';
  static const onboarding = '/onboarding';
  static const store = '/store';
  static const stats = '/stats';
  static const about = '/about';
  static const achievements = '/achievements';
  static const theme = '/settings/theme';
  static const season = '/season';
  static const versus = '/together/versus';
  static const coop = '/together/coop';
  static const trophies = '/together/trophies';
  static String match(String id) => '/together/match/$id';
  static String room(String id) => '/together/room/$id';
  static String playVersus(String puzzleId, String matchId) => '/play/$puzzleId?match=$matchId';
  static String playCoop(String puzzleId, String roomId) => '/play/$puzzleId?room=$roomId';
  static String level(int level) => '/levels/$level';
  static String pack(String id) => '/pack/$id';
  static String play(String puzzleId) => '/play/$puzzleId';
  static String leaderboard(String date, String lang) => '/leaderboard/$date?lang=$lang';
}

GoRouter buildRouter(Ref ref, {String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      if (!done && state.matchedLocation != Routes.onboarding) return Routes.onboarding;
      // Old tab paths.
      if (state.matchedLocation == '/profile') return Routes.me;
      if (state.matchedLocation == '/packs') return Routes.levels;
      return null;
    },
    routes: [
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeTab())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.daily, builder: (_, _) => const DailyTab())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.together, builder: (_, _) => const TogetherTab())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.me, builder: (_, _) => const ProfileTab())]),
        ],
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileTab()),
      GoRoute(path: '/packs', builder: (_, _) => const LevelsTab()),
      GoRoute(path: Routes.levels, builder: (_, _) => const LevelsTab()),
      GoRoute(
        path: '/levels/:level',
        builder: (_, state) => PacksOfLevelScreen(level: int.tryParse(state.pathParameters['level'] ?? '') ?? 1),
      ),
      GoRoute(path: '/pack/:packId', builder: (_, state) => PackScreen(packId: state.pathParameters['packId']!)),
      GoRoute(
        path: '/play/:puzzleId',
        builder: (_, state) => PuzzleScreen(
          puzzleId: state.pathParameters['puzzleId']!,
          matchId: state.uri.queryParameters['match'],
          roomId: state.uri.queryParameters['room'],
        ),
      ),
      GoRoute(path: Routes.season, builder: (_, _) => const SeasonScreen()),
      GoRoute(path: Routes.versus, builder: (_, _) => const VersusScreen()),
      GoRoute(path: Routes.coop, builder: (_, _) => const CoopScreen()),
      GoRoute(path: Routes.trophies, builder: (_, _) => const TrophyLeaderboardScreen()),
      GoRoute(path: '/together/match/:id', builder: (_, state) => MatchLobbyScreen(matchId: state.pathParameters['id']!)),
      GoRoute(path: '/together/room/:id', builder: (_, state) => RoomLobbyScreen(roomId: state.pathParameters['id']!)),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsTab()),
      GoRoute(path: Routes.store, builder: (_, _) => const StoreScreen()),
      GoRoute(path: Routes.stats, builder: (_, _) => const StatsScreen()),
      GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),
      GoRoute(path: Routes.achievements, builder: (_, _) => const AchievementsScreen()),
      GoRoute(path: Routes.theme, builder: (_, _) => const ThemeScreen()),
      GoRoute(
        path: '/leaderboard/:date',
        builder: (_, state) => LeaderboardScreen(
          lang: state.uri.queryParameters['lang'] ?? 'he',
          date: state.pathParameters['date']!,
        ),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});
