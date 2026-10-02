import 'package:flutter/foundation.dart';

import '../math/horizon_ffi.dart' as rust;
import 'achievements.dart';

/// Singleton game state shared across every screen (menu, game, wheel,
/// paytable, daily bonus, missions, stats). All math lives in the Rust
/// `horizon_math` static library — this Dart class is a thin
/// [ChangeNotifier] shell that forwards reads and writes across FFI and
/// pokes Flutter listeners whenever the Rust-owned state changes.
///
/// State is intentionally not persisted (resets on cold start), matching
/// the "for fun casino demo" product behaviour.
class PlayerProfile extends ChangeNotifier {
  PlayerProfile._();
  static final PlayerProfile instance = PlayerProfile._();

  // ---------- Wallet ----------
  int get coins => rust.hxProfileCoins();

  void addCoins(int amount) {
    if (amount <= 0) return;
    rust.hxProfileAddCoins(amount);
    notifyListeners();
  }

  bool spendCoins(int amount) {
    if (amount <= 0) return true;
    if (rust.hxProfileSpendCoins(amount) == 0) return false;
    notifyListeners();
    return true;
  }

  /// Rust changed the wallet behind our back (e.g. achievement claim or
  /// daily bonus); wake up listeners so coin counters refresh.
  void notifyWalletChanged() => notifyListeners();

  // ---------- Session statistics ----------
  int get totalSpins => rust.hxProfileTotalSpins();
  int get paidSpins => rust.hxProfilePaidSpins();
  int get freeSpinsPlayed => rust.hxProfileFreeSpinsPlayed();
  int get totalWagered => rust.hxProfileTotalWagered();
  int get totalWon => rust.hxProfileTotalWon();
  int get biggestWin => rust.hxProfileBiggestWin();
  int get biggestMultiplier => rust.hxProfileBiggestMult();
  int get bonusRoundsTriggered => rust.hxProfileBonusRounds();
  int get longestWinStreak => rust.hxProfileLongestWinStreak();

  /// Return-to-Player %, calculated live from wagered vs won amounts.
  double get rtp => rust.hxProfileRtpX1000() / 1000.0;

  /// Called by the game screen after each spin resolves (line wins only, the
  /// bonus wheel prize is reported via [recordBonusPrize]).
  void recordSpin({
    required int bet,
    required int win,
    required bool wasFree,
  }) {
    rust.hxProfileRecordSpin(bet, win, wasFree ? 1 : 0);
    Achievements.instance.refresh();
    notifyListeners();
  }

  void recordBonusTriggered({required int scatterCount}) {
    rust.hxProfileRecordBonusTriggered(scatterCount);
    Achievements.instance.refresh();
    notifyListeners();
  }

  void recordBonusPrize(int amount) {
    if (amount <= 0) return;
    rust.hxProfileRecordBonusPrize(amount);
    Achievements.instance.refresh();
    notifyListeners();
  }

  // ---------- Daily bonus ----------
  int get dailyStreak => rust.hxProfileDailyStreak();

  int get nextDailyReward => rust.hxProfileNextDailyReward();

  List<int> get dailyRewardTable {
    final int n = rust.hxProfileDailyTableLen();
    return <int>[for (int i = 0; i < n; i++) rust.hxProfileDailyRewardAt(i)];
  }

  bool get canClaimDaily =>
      rust.hxProfileCanClaimDaily(_nowUnixSeconds()) != 0;

  /// Time remaining until the next claim becomes available.
  Duration get timeUntilNextClaim => Duration(
        seconds: rust.hxProfileTimeUntilClaimS(_nowUnixSeconds()),
      );

  /// Attempts to claim today's reward. Returns the amount awarded, or 0
  /// when the daily bonus is still on cool-down.
  int claimDailyBonus() {
    final int reward = rust.hxProfileClaimDaily(_nowUnixSeconds());
    if (reward > 0) {
      Achievements.instance.refresh();
      notifyListeners();
    }
    return reward;
  }

  // ---------- Free spins mode ----------
  static int get freeSpinMultiplier => rust.hxProfileFreeSpinMult();

  int get freeSpinsRemaining => rust.hxProfileFreeSpinsRemaining();
  int get freeSpinsBet => rust.hxProfileFreeSpinsBet();
  bool get inFreeSpinsMode => rust.hxProfileInFreeMode() != 0;

  void grantFreeSpins({required int count, required int bet}) {
    rust.hxProfileGrantFreeSpins(count, bet);
    notifyListeners();
  }

  /// Called by the game screen when it starts a free-spin. Decrements the
  /// counter and returns the bet that should be considered wagered
  /// (still 0 to the player, but the reels use it for payout math).
  int consumeFreeSpin() {
    final int bet = rust.hxProfileConsumeFreeSpin();
    notifyListeners();
    return bet;
  }

  static int _nowUnixSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
