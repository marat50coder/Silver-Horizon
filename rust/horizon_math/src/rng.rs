// Tiny PCG-XSH-RR 64→32 RNG, seeded once from Darwin's `arc4random_buf`.
//
// Not cryptographically significant — the game is a cosmetic "fun coins"
// slot and the pay table / weights are the actual source of fairness. PCG
// gives us a stream statistically indistinguishable from uniform at a
// footprint of ~40 bytes and no dependencies.

use crate::sync_cell::IsolateCell;

extern "C" {
    fn arc4random_buf(buf: *mut u8, nbytes: usize);
}

#[inline(always)]
fn seed_from_os() -> u64 {
    let mut bytes = [0u8; 8];
    // SAFETY: arc4random_buf is thread-safe on Darwin and writes exactly
    // `nbytes` bytes into `buf`.
    unsafe { arc4random_buf(bytes.as_mut_ptr(), 8) }
    u64::from_le_bytes(bytes)
}

pub struct Pcg32 {
    state: u64,
    inc: u64,
}

impl Pcg32 {
    pub fn new() -> Self {
        let seed = seed_from_os();
        let inc = seed_from_os() | 1;
        let mut rng = Self { state: 0, inc };
        rng.state = rng
            .state
            .wrapping_add(seed)
            .wrapping_mul(6_364_136_223_846_793_005);
        rng.next_u32();
        rng.state = rng.state.wrapping_add(seed);
        rng.next_u32();
        rng
    }

    #[inline(always)]
    pub fn next_u32(&mut self) -> u32 {
        let old = self.state;
        self.state = old
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(self.inc);
        let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
        let rot = (old >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    /// Uniform integer in `[0, bound)` (bound > 0).
    #[inline(always)]
    pub fn next_bounded(&mut self, bound: u32) -> u32 {
        // Lemire's debiased modulo.
        let mut x = self.next_u32();
        let mut m = (x as u64) * (bound as u64);
        let mut l = m as u32;
        if l < bound {
            let t = bound.wrapping_neg() % bound;
            while l < t {
                x = self.next_u32();
                m = (x as u64) * (bound as u64);
                l = m as u32;
            }
        }
        (m >> 32) as u32
    }

    #[inline(always)]
    pub fn next_f32(&mut self) -> f32 {
        (self.next_u32() >> 8) as f32 * (1.0 / (1u32 << 24) as f32)
    }
}

static RNG: IsolateCell<Option<Pcg32>> = IsolateCell::new(None);

#[inline(always)]
pub fn with_rng<F, R>(f: F) -> R
where
    F: FnOnce(&mut Pcg32) -> R,
{
    let slot = RNG.get();
    if slot.is_none() {
        *slot = Some(Pcg32::new());
    }
    // SAFETY: just populated.
    f(slot.as_mut().unwrap())
}
