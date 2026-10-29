import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'multiplayer_models.dart';
import 'multiplayer_service.dart';

/// Versus / co-op backend: the deployed callables when cloud sync is on,
/// disabled otherwise. Tests override it with [FakeMultiplayerService].
final multiplayerServiceProvider = Provider<MultiplayerService>((ref) {
  final cloud = ref.watch(cloudSyncProvider);
  final uid = cloud.userId;
  if (!cloud.enabled || uid == null) return const DisabledMultiplayerService();
  return FirebaseMultiplayerService(uid: uid);
});

final multiplayerEnabledProvider = Provider<bool>((ref) => ref.watch(multiplayerServiceProvider).enabled);

/// Live `matches/{id}` document.
final matchStreamProvider = StreamProvider.autoDispose.family<MatchDoc?, String>(
  (ref, matchId) => ref.watch(multiplayerServiceProvider).watchMatch(matchId),
);

/// Live `coopRooms/{id}` document.
final roomStreamProvider = StreamProvider.autoDispose.family<CoopRoomDoc?, String>(
  (ref, roomId) => ref.watch(multiplayerServiceProvider).watchRoom(roomId),
);

/// Live `coopRooms/{id}/cells`.
final roomCellsProvider = StreamProvider.autoDispose.family<List<CoopCell>, String>(
  (ref, roomId) => ref.watch(multiplayerServiceProvider).watchCells(roomId),
);

/// Trophy leaderboard of a language (null = unavailable).
final trophyBoardProvider = FutureProvider.autoDispose.family<TrophyBoard?, String>(
  (ref, lang) => ref.watch(multiplayerServiceProvider).trophyLeaderboard(lang: lang),
);

/// Member colours (0..3) for co-op cursors and freshly placed letters.
const coopColors = [Color(0xFF1F8A8A), Color(0xFFE25D5D), Color(0xFF5B6FB8), Color(0xFFB8860B)];

Color coopColor(int index) => coopColors[index.clamp(0, coopColors.length - 1)];
