// Raw `dart:ffi` bindings over the horizon_math Rust dynamic library.
//
// On Android the crate is cross-compiled with cargo-ndk into a cdylib
// (`libhorizon_math.so`) for every supported ABI (arm64-v8a, armeabi-v7a,
// x86_64, x86). Gradle picks the .so files out of
// `android/app/src/main/jniLibs/<abi>/` and bundles them into the APK/AAB
// — the Android loader then resolves the library by name through
// `DynamicLibrary.open('libhorizon_math.so')`.
//
// Everything here is 1:1 with `rust/horizon_math/include/horizon_math.h`.
// Keep both files in sync when a new entry point is added.
//
// This file deliberately does NOT depend on Flutter.

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

final ffi.DynamicLibrary _lib = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libhorizon_math.so')
    : ffi.DynamicLibrary.process();

// ----- meta -----

final int Function() hxVersion = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_version')
    .asFunction<int Function()>();

/// Resolved on first call so a release binary that never asks for the
/// boost, and the widget test that never enters `main`, do not have to
/// look the symbol up at library load.
void Function(int)? _hxSetDebugBonus;

void hxSetDebugBonus(int enabled) {
  _hxSetDebugBonus ??= _lib
      .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Uint8)>>(
        'hx_set_debug_bonus',
      )
      .asFunction<void Function(int)>();
  _hxSetDebugBonus!(enabled);
}

// ----- symbols -----

final int Function() hxSymbolCount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_symbol_count')
    .asFunction<int Function()>();

final int Function(int) hxSymbolIsScatter = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint8)>>(
        'hx_symbol_is_scatter')
    .asFunction<int Function(int)>();

final int Function(int) hxSymbolIsWild = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint8)>>(
        'hx_symbol_is_wild')
    .asFunction<int Function(int)>();

final int Function(int, int) hxSymbolPayout = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint8, ffi.Uint8)>>(
        'hx_symbol_payout')
    .asFunction<int Function(int, int)>();

final int Function() hxPickWeighted = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function()>>('hx_pick_weighted')
    .asFunction<int Function()>();

// ----- paylines -----

final int Function() hxPaylineCount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_payline_count')
    .asFunction<int Function()>();

final int Function(int, int) hxPaylineRow = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32, ffi.Uint32)>>(
        'hx_payline_row')
    .asFunction<int Function(int, int)>();

// ----- spin -----

final int Function(int) hxSpin = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>('hx_spin')
    .asFunction<int Function(int)>();

final int Function(int, int) hxLastGridAt = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32, ffi.Uint32)>>(
        'hx_last_grid_at')
    .asFunction<int Function(int, int)>();

final int Function() hxLastLineCount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_last_line_count')
    .asFunction<int Function()>();

final int Function(int) hxLastLinePayline = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32)>>(
        'hx_last_line_payline')
    .asFunction<int Function(int)>();

final int Function(int) hxLastLineSymbol = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32)>>(
        'hx_last_line_symbol')
    .asFunction<int Function(int)>();

final int Function(int) hxLastLineMatchCount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32)>>(
        'hx_last_line_match_count')
    .asFunction<int Function(int)>();

final int Function(int) hxLastLineAmount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>(
        'hx_last_line_amount')
    .asFunction<int Function(int)>();

final int Function() hxLastScatterCount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>(
        'hx_last_scatter_count')
    .asFunction<int Function()>();

final int Function(int) hxLastScatterPacked = _lib
    .lookup<ffi.NativeFunction<ffi.Uint16 Function(ffi.Uint32)>>(
        'hx_last_scatter_packed')
    .asFunction<int Function(int)>();

final int Function() hxLastTotal = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_last_total')
    .asFunction<int Function()>();

// ----- bonus -----

final int Function() hxBonusSliceCount = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_bonus_slice_count')
    .asFunction<int Function()>();

final int Function() hxBonusFreeSpinsMarker = _lib
    .lookup<ffi.NativeFunction<ffi.Int32 Function()>>(
        'hx_bonus_free_spins_marker')
    .asFunction<int Function()>();

final int Function(int, int) hxBonusMultiplier = _lib
    .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Uint32, ffi.Uint32)>>(
        'hx_bonus_multiplier')
    .asFunction<int Function(int, int)>();

final int Function(int, int) hxBonusIsFreeSlice = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32, ffi.Uint32)>>(
        'hx_bonus_is_free_slice')
    .asFunction<int Function(int, int)>();

final int Function(int, int) hxBonusRoll = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32, ffi.Uint32)>>(
        'hx_bonus_roll')
    .asFunction<int Function(int, int)>();

final int Function() hxBonusLastCoins = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>('hx_bonus_last_coins')
    .asFunction<int Function()>();

final int Function() hxBonusLastFreeSpins = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>(
        'hx_bonus_last_free_spins')
    .asFunction<int Function()>();

// ----- big win -----

final int Function(int) hxBigWinTier = _lib
    .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Uint32)>>(
        'hx_big_win_tier')
    .asFunction<int Function(int)>();

// ----- profile wallet -----

final int Function() hxProfileCoins = _lib
    .lookup<ffi.NativeFunction<ffi.Int64 Function()>>('hx_profile_coins')
    .asFunction<int Function()>();

final void Function(int) hxProfileAddCoins = _lib
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int64)>>(
        'hx_profile_add_coins')
    .asFunction<void Function(int)>();

final int Function(int) hxProfileSpendCoins = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Int64)>>(
        'hx_profile_spend_coins')
    .asFunction<int Function(int)>();

// ----- profile stats -----

final void Function(int, int, int) hxProfileRecordSpin = _lib
    .lookup<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Int64, ffi.Int64, ffi.Uint8)>>(
        'hx_profile_record_spin')
    .asFunction<void Function(int, int, int)>();

final void Function(int) hxProfileRecordBonusTriggered = _lib
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Uint32)>>(
        'hx_profile_record_bonus_triggered')
    .asFunction<void Function(int)>();

final void Function(int) hxProfileRecordBonusPrize = _lib
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int64)>>(
        'hx_profile_record_bonus_prize')
    .asFunction<void Function(int)>();

int Function() _u64(String name) => _lib
    .lookup<ffi.NativeFunction<ffi.Uint64 Function()>>(name)
    .asFunction<int Function()>();

int Function() _u32(String name) => _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function()>>(name)
    .asFunction<int Function()>();

final int Function() hxProfileTotalSpins = _u64('hx_profile_total_spins');
final int Function() hxProfilePaidSpins = _u64('hx_profile_paid_spins');
final int Function() hxProfileFreeSpinsPlayed =
    _u64('hx_profile_free_spins_played');
final int Function() hxProfileTotalWagered = _u64('hx_profile_total_wagered');
final int Function() hxProfileTotalWon = _u64('hx_profile_total_won');
final int Function() hxProfileBiggestWin = _u64('hx_profile_biggest_win');
final int Function() hxProfileBiggestMult = _u32('hx_profile_biggest_mult');
final int Function() hxProfileBonusRounds = _u32('hx_profile_bonus_rounds');
final int Function() hxProfileLongestWinStreak =
    _u32('hx_profile_longest_win_streak');
final int Function() hxProfileRtpX1000 = _u64('hx_profile_rtp_x1000');

// ----- profile free spins -----

final void Function(int, int) hxProfileGrantFreeSpins = _lib
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Uint32, ffi.Uint32)>>(
        'hx_profile_grant_free_spins')
    .asFunction<void Function(int, int)>();

final int Function() hxProfileConsumeFreeSpin =
    _u32('hx_profile_consume_free_spin');
final int Function() hxProfileFreeSpinsRemaining =
    _u32('hx_profile_free_spins_remaining');
final int Function() hxProfileFreeSpinsBet = _u32('hx_profile_free_spins_bet');
final int Function() hxProfileInFreeMode = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function()>>('hx_profile_in_free_mode')
    .asFunction<int Function()>();
final int Function() hxProfileFreeSpinMult = _u32('hx_profile_free_spin_mult');

// ----- profile daily -----

final int Function(int) hxProfileCanClaimDaily = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Int64)>>(
        'hx_profile_can_claim_daily')
    .asFunction<int Function(int)>();

final int Function() hxProfileDailyStreak = _u32('hx_profile_daily_streak');
final int Function() hxProfileNextDailyReward =
    _u32('hx_profile_next_daily_reward');

final int Function(int) hxProfileDailyRewardAt = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>(
        'hx_profile_daily_reward_at')
    .asFunction<int Function(int)>();

final int Function() hxProfileDailyTableLen =
    _u32('hx_profile_daily_table_len');

final int Function(int) hxProfileTimeUntilClaimS = _lib
    .lookup<ffi.NativeFunction<ffi.Int64 Function(ffi.Int64)>>(
        'hx_profile_time_until_claim_s')
    .asFunction<int Function(int)>();

final int Function(int) hxProfileClaimDaily = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Int64)>>(
        'hx_profile_claim_daily')
    .asFunction<int Function(int)>();

// ----- achievements -----

final int Function() hxAchCount = _u32('hx_ach_count');

final int Function(int) hxAchTarget = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>(
        'hx_ach_target')
    .asFunction<int Function(int)>();

final int Function(int) hxAchReward = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>(
        'hx_ach_reward')
    .asFunction<int Function(int)>();

final int Function(int) hxAchProgress = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>(
        'hx_ach_progress')
    .asFunction<int Function(int)>();

final int Function(int) hxAchClaimed = _lib
    .lookup<ffi.NativeFunction<ffi.Uint8 Function(ffi.Uint32)>>(
        'hx_ach_claimed')
    .asFunction<int Function(int)>();

final int Function() hxAchCompletedCount = _u32('hx_ach_completed_count');
final int Function() hxAchClaimableCount = _u32('hx_ach_claimable_count');

final int Function(int) hxAchClaim = _lib
    .lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Uint32)>>(
        'hx_ach_claim')
    .asFunction<int Function(int)>();
