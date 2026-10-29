import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../meta/game_events_controller.dart';
import 'profile_model.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => JsonProfileRepository(ref.watch(jsonStoreProvider)));

/// Player profile. Starts with defaults and loads the stored profile; every
/// change is persisted and pushed to the cloud when sync is on.
class ProfileController extends Notifier<ProfileData> {
  @override
  ProfileData build() {
    // Apply the stored profile unless the player already changed something.
    ref.read(profileRepositoryProvider).load().then((p) {
      if (state.updatedAt == 0) state = p;
    }).ignore();
    return const ProfileData();
  }

  void _set(ProfileData next) {
    state = next.copyWith(updatedAt: ref.read(clockProvider).nowMs);
    ref.read(profileRepositoryProvider).save(state).ignore();
    final cloud = ref.read(cloudSyncProvider);
    if (cloud.enabled) cloud.pushProfile(state.toJson()).ignore();
  }

  void setDisplayName(String? name) {
    final trimmed = name?.trim();
    _set(state.copyWith(displayName: trimmed, clearName: trimmed == null || trimmed.isEmpty));
  }

  void setAvatar(String id) => _set(state.copyWith(avatarId: id));

  void reset() => _set(const ProfileData());
}

final profileProvider = NotifierProvider<ProfileController, ProfileData>(ProfileController.new);

final rankProvider = Provider<Rank>((ref) => Ranks.forPuzzles(ref.watch(playerStatsProvider).puzzlesCompleted));
