import 'package:flutter/services.dart';

/// Tactile feedback. Settings decide between [SystemHaptics] and [NoHaptics].
abstract class Haptics {
  const Haptics();
  Future<void> tick();
  Future<void> success();
  Future<void> error();
}

class SystemHaptics extends Haptics {
  const SystemHaptics();
  @override
  Future<void> tick() => HapticFeedback.selectionClick();
  @override
  Future<void> success() => HapticFeedback.mediumImpact();
  @override
  Future<void> error() => HapticFeedback.heavyImpact();
}

class NoHaptics extends Haptics {
  const NoHaptics();
  @override
  Future<void> tick() async {}
  @override
  Future<void> success() async {}
  @override
  Future<void> error() async {}
}

enum SoundCue { key, wordCorrect, wordWrong, puzzleComplete, hint }

/// Optional sounds. No sound assets ship in this build, so the only
/// implementation is a no-op; a real player can be dropped in behind this
/// interface without touching callers.
abstract class Sounds {
  const Sounds();
  Future<void> play(SoundCue cue);
}

class NoSounds extends Sounds {
  const NoSounds();
  @override
  Future<void> play(SoundCue cue) async {}
}

/// Records cues instead of playing them (tests).
class RecordingSounds extends Sounds {
  final List<SoundCue> played = [];
  @override
  Future<void> play(SoundCue cue) async => played.add(cue);
}
