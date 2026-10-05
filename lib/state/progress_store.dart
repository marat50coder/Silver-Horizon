import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../math/horizon_ffi.dart' as rust;
import 'achievements.dart';
import 'player_profile.dart';

/// Saves the Rust-owned game state (wallet, stats, free spins, daily bonus,
/// achievements) to a small JSON file and restores it on the next launch.
///
/// Rust exposes every persistent number by index (`hx_state_*`); the index
/// order is append-only, so files written by older builds still load.
class ProgressStore with WidgetsBindingObserver {
  ProgressStore._();
  static final ProgressStore instance = ProgressStore._();

  static const int _schema = 1;
  static const Duration _debounce = Duration(milliseconds: 400);

  File? _file;
  Timer? _pending;

  /// Call once after `WidgetsFlutterBinding.ensureInitialized()` and before
  /// `runApp`, so the first frame already shows the saved coin balance.
  void init() {
    _file = _resolveFile();
    _load();
    PlayerProfile.instance.addListener(_scheduleSave);
    Achievements.instance.addListener(_scheduleSave);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      flush();
    }
  }

  void _scheduleSave() {
    _pending?.cancel();
    _pending = Timer(_debounce, flush);
  }

  /// Writes the current state immediately.
  void flush() {
    _pending?.cancel();
    _pending = null;
    final File? file = _file;
    if (file == null) return;
    final int n = rust.hxStateFieldCount();
    final String data = jsonEncode(<String, Object>{
      'v': _schema,
      's': <int>[for (int i = 0; i < n; i++) rust.hxStateGet(i)],
    });
    try {
      file.parent.createSync(recursive: true);
      // Write-then-rename so a crash mid-write never leaves a torn file.
      final File tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(data, flush: true);
      tmp.renameSync(file.path);
    } catch (_) {
      // Saving is best effort; the game keeps working from memory.
    }
  }

  void _load() {
    final File? file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return;
      final Object? values = decoded['s'];
      if (values is! List) return;
      final int n = rust.hxStateFieldCount();
      for (int i = 0; i < values.length && i < n; i++) {
        final Object? v = values[i];
        if (v is int) rust.hxStateSet(i, v);
      }
    } catch (_) {
      // A corrupt file just means starting fresh.
    }
  }

  static File? _resolveFile() {
    // iOS sandbox: $HOME is the app container; Application Support is
    // private to the app and included in device backups.
    final String? home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return File('$home/Library/Application Support/progress.json');
  }
}
