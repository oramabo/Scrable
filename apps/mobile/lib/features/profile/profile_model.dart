import 'package:flutter/material.dart';

import '../../core/storage/json_store.dart';

/// Locally stored player profile. Synced to `users/{uid}.profile` when cloud
/// sync is on.
class ProfileData {
  const ProfileData({this.displayName, this.avatarId = 'arrow', this.updatedAt = 0});

  /// Null = the localised default ("פותר/ת" / "Solver").
  final String? displayName;
  final String avatarId;
  final int updatedAt;

  ProfileData copyWith({String? displayName, bool clearName = false, String? avatarId, int? updatedAt}) => ProfileData(
        displayName: clearName ? null : (displayName ?? this.displayName),
        avatarId: avatarId ?? this.avatarId,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        if (displayName != null) 'displayName': displayName,
        'avatarId': avatarId,
        'updatedAt': updatedAt,
      };

  static ProfileData fromJson(Map<String, dynamic> j) => ProfileData(
        displayName: j['displayName'] as String?,
        avatarId: (j['avatarId'] as String?) ?? 'arrow',
        updatedAt: (j['updatedAt'] as int?) ?? 0,
      );
}

/// Built-in vector avatars: a Material icon on a coloured disc.
class Avatar {
  const Avatar(this.id, this.icon, this.color, {required this.nameHe, required this.nameEn});
  final String id;
  final IconData icon;
  final Color color;
  final String nameHe;
  final String nameEn;

  String name(String lang) => lang == 'he' ? nameHe : nameEn;
}

abstract final class Avatars {
  static const all = [
    Avatar('arrow', Icons.arrow_forward_rounded, Color(0xFFB5471F), nameHe: 'חץ', nameEn: 'Arrow'),
    Avatar('owl', Icons.nightlight_round, Color(0xFF5B6FB8), nameHe: 'ינשוף', nameEn: 'Owl'),
    Avatar('fox', Icons.pets_rounded, Color(0xFFE0652A), nameHe: 'שועל', nameEn: 'Fox'),
    Avatar('book', Icons.menu_book_rounded, Color(0xFF2F6F6D), nameHe: 'ספר', nameEn: 'Book'),
    Avatar('star', Icons.star_rounded, Color(0xFFE0A526), nameHe: 'כוכב', nameEn: 'Star'),
    Avatar('bolt', Icons.bolt_rounded, Color(0xFF7B3FA0), nameHe: 'ברק', nameEn: 'Bolt'),
    Avatar('leaf', Icons.eco_rounded, Color(0xFF3E8E41), nameHe: 'עלה', nameEn: 'Leaf'),
    Avatar('coffee', Icons.coffee_rounded, Color(0xFF795548), nameHe: 'קפה', nameEn: 'Coffee'),
    Avatar('rocket', Icons.rocket_launch_rounded, Color(0xFF1E88E5), nameHe: 'רקטה', nameEn: 'Rocket'),
    Avatar('music', Icons.music_note_rounded, Color(0xFFD81B60), nameHe: 'תו', nameEn: 'Note'),
    Avatar('puzzle', Icons.extension_rounded, Color(0xFF00897B), nameHe: 'פאזל', nameEn: 'Puzzle'),
    Avatar('sun', Icons.wb_sunny_rounded, Color(0xFFF9A825), nameHe: 'שמש', nameEn: 'Sun'),
  ];

  static Avatar byId(String id) => all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

abstract class ProfileRepository {
  Future<ProfileData> load();
  Future<void> save(ProfileData profile);
}

class JsonProfileRepository implements ProfileRepository {
  JsonProfileRepository(this.store, {this.key = 'profile'});
  final JsonStore store;
  final String key;

  @override
  Future<ProfileData> load() async {
    final j = await store.read(key);
    return j == null ? const ProfileData() : ProfileData.fromJson(j);
  }

  @override
  Future<void> save(ProfileData profile) => store.write(key, profile.toJson());
}
