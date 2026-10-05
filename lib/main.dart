import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'math/horizon_ffi.dart' as rust;
import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Release APKs compile with kDebugMode == false, so the scatter table
  // stays at the production weight. Debug runs (flutter run / debug APK)
  // boost the bonus-wheel hit rate so the wheel can be tested quickly.
  if (kDebugMode) {
    rust.hxSetDebugBonus(1);
  }
  // Portrait orientation is enforced from the game screen only; the loading
  // screen supports both portrait and landscape.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const GoldenCrownApp());
}

class GoldenCrownApp extends StatelessWidget {
  const GoldenCrownApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Precache the loading screen art so the very first Flutter frame already
    // has its background rendered — otherwise the user sees a black flash
    // between the native launch image and Flutter's first paint.
    precacheImage(
      const AssetImage(
        'assets/Silver_Horizon_additional_assets/Vertical_Loading_Screen.webp',
      ),
      context,
    );
    precacheImage(
      const AssetImage(
        'assets/Silver_Horizon_additional_assets/Horizontal_Loading_Screen.webp',
      ),
      context,
    );

    return MaterialApp(
      title: 'Golden Crown',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A6FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
      ),
      home: const LoadingScreen(),
    );
  }
}
