import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'state/progress_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ProgressStore.instance.init();
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
  runApp(const SilverHorizonApp());
}

class SilverHorizonApp extends StatelessWidget {
  const SilverHorizonApp({super.key});

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
      title: 'Silver Horizon',
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
