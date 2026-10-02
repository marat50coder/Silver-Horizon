import 'package:flutter/foundation.dart';

import '../math/horizon_ffi.dart' as rust;
import 'player_profile.dart';

/// Simple "missions" system. Every achievement has a target value and a
/// coin reward the player can claim once it fills up.
///
/// Progress + reward amounts live in Rust (`rust/horizon_math/src/ach.rs`).
/// Dart owns the human-readable title / description per achievement and
/// forwards claim requests through FFI. The order of entries in
/// [_definitions] MUST match the index constants in `src/ach.rs`
/// (`FIRST_STEPS = 0, SEASONED = 1, ...`).
class Achievement {
  Achievement({
    required this.id,
    required this.rustIndex,
    required this.title,
    required this.description,
  });

  final String id;
  final int rustIndex;
  final String title;
  final String description;

  int get target => rust.hxAchTarget(rustIndex);
  int get reward => rust.hxAchReward(rustIndex);
  int get progress => rust.hxAchProgress(rustIndex);
  bool get claimed => rust.hxAchClaimed(rustIndex) != 0;

  double get percent {
    final int t = target;
    if (t == 0) return 1;
    return (progress / t).clamp(0, 1);
  }

  bool get completed => progress >= target;
  bool get claimable => completed && !claimed;
}

class Achievements extends ChangeNotifier {
  Achievements._();
  static final Achievements instance = Achievements._();

  late final List<Achievement> _list = <Achievement>[
    Achievement(
      id: 'first_steps',
      rustIndex: 0,
      title: 'First Steps',
      description: 'Spin the reels 10 times',
    ),
    Achievement(
      id: 'seasoned',
      rustIndex: 1,
      title: 'Seasoned Player',
      description: 'Spin the reels 100 times',
    ),
    Achievement(
      id: 'big_hitter',
      rustIndex: 2,
      title: 'Big Hitter',
      description: 'Win a single spin worth x10 your bet',
    ),
    Achievement(
      id: 'mega_hitter',
      rustIndex: 3,
      title: 'Mega Hitter',
      description: 'Win a single spin worth x50 your bet',
    ),
    Achievement(
      id: 'bonus_hunter',
      rustIndex: 4,
      title: 'Bonus Hunter',
      description: 'Trigger the bonus wheel 3 times',
    ),
    Achievement(
      id: 'mega_bonus',
      rustIndex: 5,
      title: 'Mega Bonus',
      description: 'Trigger the bonus with 4 scatters',
    ),
    Achievement(
      id: 'hot_streak',
      rustIndex: 6,
      title: 'Hot Streak',
      description: 'Win 5 spins in a row',
    ),
    Achievement(
      id: 'daily_devotion',
      rustIndex: 7,
      title: 'Daily Devotion',
      description: 'Claim the daily bonus 3 times',
    ),
  ];

  List<Achievement> get all => List<Achievement>.unmodifiable(_list);

  int get completedCount => rust.hxAchCompletedCount();
  int get claimableCount => rust.hxAchClaimableCount();

  Achievement? byId(String id) {
    for (final Achievement a in _list) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Called by [PlayerProfile] after any spin / bonus / daily event. Rust
  /// has already updated the progress counters; this just pokes Flutter
  /// so UI subscribers rebuild.
  void refresh() => notifyListeners();

  /// Awards the reward for a completed achievement. Returns `false` when
  /// the achievement is not claimable (incomplete or already claimed).
  bool claim(PlayerProfile p, Achievement a) {
    final int reward = rust.hxAchClaim(a.rustIndex);
    if (reward == 0) return false;
    // Rust credits the wallet; wake listeners so coin counters update.
    p.notifyWalletChanged();
    notifyListeners();
    return true;
  }
}
