// C ABI for the horizon_math Rust static library.
//
// Mirrors `rust/horizon_math/src/ffi.rs`. Keep both files in sync when
// adding a new entry point.
//
// Consumers:
//   - ios/Runner/RustGlue.swift takes `&hx_*` pointers so dead-strip
//     cannot drop these symbols from the release binary.
//   - lib/math/bindings.dart loads them from the main executable at
//     runtime via `DynamicLibrary.process()`.

#ifndef HORIZON_MATH_H
#define HORIZON_MATH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* meta */
uint32_t hx_version(void);
void     hx_set_debug_bonus(uint8_t enabled);

/* symbols */
uint32_t hx_symbol_count(void);
uint8_t  hx_symbol_is_scatter(uint8_t sym);
uint8_t  hx_symbol_is_wild(uint8_t sym);
uint32_t hx_symbol_payout(uint8_t sym, uint8_t count);
uint8_t  hx_pick_weighted(void);

/* paylines */
uint32_t hx_payline_count(void);
uint8_t  hx_payline_row(uint32_t line_idx, uint32_t col);

/* spin */
uint32_t hx_spin(uint32_t bet);
uint8_t  hx_last_grid_at(uint32_t col, uint32_t row);
uint32_t hx_last_line_count(void);
uint8_t  hx_last_line_payline(uint32_t idx);
uint8_t  hx_last_line_symbol(uint32_t idx);
uint8_t  hx_last_line_match_count(uint32_t idx);
uint32_t hx_last_line_amount(uint32_t idx);
uint32_t hx_last_scatter_count(void);
uint16_t hx_last_scatter_packed(uint32_t idx);
uint32_t hx_last_total(void);

/* bonus */
uint32_t hx_bonus_slice_count(void);
int32_t  hx_bonus_free_spins_marker(void);
int32_t  hx_bonus_multiplier(uint32_t scatter_count, uint32_t slice);
uint8_t  hx_bonus_is_free_slice(uint32_t scatter_count, uint32_t slice);
uint32_t hx_bonus_roll(uint32_t scatter_count, uint32_t bet);
uint32_t hx_bonus_last_coins(void);
uint32_t hx_bonus_last_free_spins(void);

/* big win */
int32_t  hx_big_win_tier(uint32_t multiplier);

/* profile wallet */
int64_t  hx_profile_coins(void);
void     hx_profile_add_coins(int64_t amount);
uint8_t  hx_profile_spend_coins(int64_t amount);

/* profile stats */
void     hx_profile_record_spin(int64_t bet, int64_t win, uint8_t was_free);
void     hx_profile_record_bonus_triggered(uint32_t scatters);
void     hx_profile_record_bonus_prize(int64_t amount);
uint64_t hx_profile_total_spins(void);
uint64_t hx_profile_paid_spins(void);
uint64_t hx_profile_free_spins_played(void);
uint64_t hx_profile_total_wagered(void);
uint64_t hx_profile_total_won(void);
uint64_t hx_profile_biggest_win(void);
uint32_t hx_profile_biggest_mult(void);
uint32_t hx_profile_bonus_rounds(void);
uint32_t hx_profile_longest_win_streak(void);
uint64_t hx_profile_rtp_x1000(void);

/* profile free spins */
void     hx_profile_grant_free_spins(uint32_t count, uint32_t bet);
uint32_t hx_profile_consume_free_spin(void);
uint32_t hx_profile_free_spins_remaining(void);
uint32_t hx_profile_free_spins_bet(void);
uint8_t  hx_profile_in_free_mode(void);
uint32_t hx_profile_free_spin_mult(void);

/* profile daily */
uint8_t  hx_profile_can_claim_daily(int64_t now_unix_s);
uint32_t hx_profile_daily_streak(void);
uint32_t hx_profile_next_daily_reward(void);
uint32_t hx_profile_daily_reward_at(uint32_t streak);
uint32_t hx_profile_daily_table_len(void);
int64_t  hx_profile_time_until_claim_s(int64_t now_unix_s);
uint32_t hx_profile_claim_daily(int64_t now_unix_s);

/* achievements */
uint32_t hx_ach_count(void);
uint32_t hx_ach_target(uint32_t id);
uint32_t hx_ach_reward(uint32_t id);
uint32_t hx_ach_progress(uint32_t id);
uint8_t  hx_ach_claimed(uint32_t id);
uint32_t hx_ach_completed_count(void);
uint32_t hx_ach_claimable_count(void);
uint32_t hx_ach_claim(uint32_t id);

#ifdef __cplusplus
}
#endif

#endif /* HORIZON_MATH_H */
