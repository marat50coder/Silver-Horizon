#import "GeneratedPluginRegistrant.h"

// Rust math library — exposes `hx_*` symbols so Swift can take function
// pointers (see RustGlue.swift) and keep the linker from dead-stripping
// them in release builds. The Dart UI resolves them at runtime via
// `DynamicLibrary.process()`.
#import "horizon_math.h"
