import Foundation

/// Keeps every `hx_*` symbol from the horizon_math static library alive
/// through the release linker's dead-strip pass.
///
/// Rust emits the FFI exports with `#[no_mangle] pub extern "C"`, but on
/// iOS release builds `DEAD_CODE_STRIPPING = YES` drops any symbol with
/// no reference inside the final binary graph. Dart resolves them at
/// runtime via `DynamicLibrary.process().lookupFunction(...)`, which is
/// invisible to the linker — so without a visible compile-time reference
/// the linker happily throws them away and the Dart lookup fails with
/// `Invalid argument(s): Failed to lookup symbol 'hx_...'`.
///
/// The fix: take a pointer to every export, XOR all the pointer values
/// into a `nonisolated(unsafe)` global sink. Because the sink is observable
/// outside this function and depends on the actual numeric value of every
/// function pointer, the Swift optimiser cannot constant-fold the array
/// (and dead-strip cannot drop the referenced symbols). `AppDelegate`
/// calls `RustGlue.ensureLinked()` once at launch.
enum RustGlue {
    @inline(never)
    static func ensureLinked() {
        let refs: [UnsafeRawPointer] = [
            unsafeBitCast(hx_version as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_symbol_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_symbol_is_scatter as @convention(c) (UInt8) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_symbol_is_wild as @convention(c) (UInt8) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_symbol_payout as @convention(c) (UInt8, UInt8) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_pick_weighted as @convention(c) () -> UInt8, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_payline_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_payline_row as @convention(c) (UInt32, UInt32) -> UInt8, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_spin as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_grid_at as @convention(c) (UInt32, UInt32) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_line_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_line_payline as @convention(c) (UInt32) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_line_symbol as @convention(c) (UInt32) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_line_match_count as @convention(c) (UInt32) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_line_amount as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_scatter_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_scatter_packed as @convention(c) (UInt32) -> UInt16, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_last_total as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_bonus_slice_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_bonus_free_spins_marker as @convention(c) () -> Int32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_bonus_multiplier as @convention(c) (UInt32, UInt32) -> Int32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_bonus_is_free_slice as @convention(c) (UInt32, UInt32) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_bonus_roll as @convention(c) (UInt32, UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_bonus_last_coins as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_bonus_last_free_spins as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_big_win_tier as @convention(c) (UInt32) -> Int32, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_profile_coins as @convention(c) () -> Int64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_add_coins as @convention(c) (Int64) -> Void, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_spend_coins as @convention(c) (Int64) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_record_spin as @convention(c) (Int64, Int64, UInt8) -> Void, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_record_bonus_triggered as @convention(c) (UInt32) -> Void, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_record_bonus_prize as @convention(c) (Int64) -> Void, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_total_spins as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_paid_spins as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_free_spins_played as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_total_wagered as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_total_won as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_biggest_win as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_biggest_mult as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_bonus_rounds as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_longest_win_streak as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_rtp_x1000 as @convention(c) () -> UInt64, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_profile_grant_free_spins as @convention(c) (UInt32, UInt32) -> Void, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_consume_free_spin as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_free_spins_remaining as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_free_spins_bet as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_in_free_mode as @convention(c) () -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_free_spin_mult as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_profile_can_claim_daily as @convention(c) (Int64) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_daily_streak as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_next_daily_reward as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_daily_reward_at as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_daily_table_len as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_time_until_claim_s as @convention(c) (Int64) -> Int64, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_profile_claim_daily as @convention(c) (Int64) -> UInt32, to: UnsafeRawPointer.self),

            unsafeBitCast(hx_ach_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_target as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_reward as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_progress as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_claimed as @convention(c) (UInt32) -> UInt8, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_completed_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_claimable_count as @convention(c) () -> UInt32, to: UnsafeRawPointer.self),
            unsafeBitCast(hx_ach_claim as @convention(c) (UInt32) -> UInt32, to: UnsafeRawPointer.self),
        ]
        // XOR every function pointer's numeric value into a global sink.
        // The sink is observable (nonisolated(unsafe) static var) and the
        // compiler cannot prove its post-condition is unused, so each
        // pointer load must survive — and so must the symbol being
        // pointed to. This is the robust alternative to `-u _hx_*`
        // linker flags, scaling to any number of exports without a
        // single new linker flag per entry point.
        var sink: UInt = 0
        for p in refs {
            sink ^= UInt(bitPattern: p)
        }
        linkedSink = sink

        #if DEBUG
        print("RustGlue: linked \(refs.count) hx_* exports (hx_version=\(hx_version()))")
        #endif
    }

    /// Global sink the ensureLinked XOR writes into. Published as
    /// `nonisolated(unsafe)` so Swift concurrency does not insist on
    /// isolation (we touch it exactly once at launch from `AppDelegate`).
    nonisolated(unsafe) static var linkedSink: UInt = 0
}
