// Single-isolate mutable state cell.
//
// Flutter runs all Dart UI code on one isolate; the game never spawns a
// second isolate that would also call FFI. Wrapping state in a plain
// `UnsafeCell` with a manual `unsafe impl Sync` avoids pulling the std
// `Mutex` + the entire lock_api machinery into the static lib (both are
// easy to fingerprint and bloat the __TEXT segment).
//
// If future features add a second isolate that calls into Rust, replace
// this with `spin::Mutex` or `std::sync::Mutex`. Debug builds assert the
// single-thread invariant.

use core::cell::UnsafeCell;

pub struct IsolateCell<T> {
    value: UnsafeCell<T>,
}

// SAFETY: see module docs. Caller contract: all FFI entry points run on
// the single UI isolate.
unsafe impl<T: Send> Sync for IsolateCell<T> {}

impl<T> IsolateCell<T> {
    pub const fn new(value: T) -> Self {
        Self {
            value: UnsafeCell::new(value),
        }
    }

    #[inline(always)]
    #[allow(clippy::mut_from_ref)]
    pub fn get(&self) -> &mut T {
        // SAFETY: see module docs.
        unsafe { &mut *self.value.get() }
    }
}
