import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Reads the `game_config` JSON parameter from Firebase Remote Config. Only
/// called when Firebase initialised successfully; any failure yields null and
/// the app keeps [GameConfig] defaults.
Future<Map<String, dynamic>?> fetchRemoteGameConfig({String key = 'game_config'}) async {
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 8),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.fetchAndActivate();
    final raw = rc.getString(key);
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (e) {
    debugPrint('remote config unavailable: $e');
    return null;
  }
}
