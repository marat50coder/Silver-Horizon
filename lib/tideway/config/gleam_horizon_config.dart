import '../core/gleam_codec.dart';

/// Encoded operational values for Silver Horizon. Privacy / support stay
/// plaintext — those URLs are already public on the legal pages.
abstract final class GleamHorizonConfig {
  static const String appTitle = 'Silver Horizon';
  static const String bundleId = 'com.silverhorizon.horizongame';
  static const String iosStoreId = '6817293412';

  static const String privacyUrl =
      'https://silverhorrizon.com/privacy-policy.html';
  static const String supportUrl = 'https://silverhorrizon.com/support.html';

  static const int pushSnoozeSeconds = 216000;
  static const int organicRecheckSeconds = 8;
  static const int savedUrlExpiryDays = 9;
  static const int exchangeTimeoutSeconds = 18;
  static const int installSignalSeconds = 22;
  static const int deepLinkSeconds = 6;
  static const int attWaitSeconds = 5;
  static const int attPromptDelayMs = 410;
  static const int gcdTimeoutSeconds = 14;

  static const List<int> _endpoint = <int>[
    40, 14, 11, 55, 189, 185, 142, 250, 65, 117, 110, 41, 177, 156, 131,
    188, 48, 125, 68, 35, 41, 198, 216, 136, 199, 63, 56, 12, 89, 213, 191,
    132, 173, 10, 10, 15, 76,
  ];
  static const List<int> _appsFlyerKey = <int>[
    5, 9, 18, 2, 155, 193, 226, 172, 119, 81, 79, 18, 152, 191, 216, 163, 5,
    78, 87, 32, 116, 197,
  ];
  static const List<int> _firebaseProject = <int>[
    114, 75, 75, 118, 246, 187, 146, 227, 5, 36, 55,
  ];
  static const List<int> _gcd = <int>[
    40, 14, 11, 55, 189, 185, 142, 250, 85, 127, 102, 44, 176, 133, 197, 178,
    50, 127, 94, 63, 42, 209, 147, 153, 134, 49, 120, 2, 25, 210, 183, 158,
    190, 69, 22, 11, 99, 162, 226, 143, 203, 8, 51, 68, 112, 128, 193,
  ];
  static const List<int> _oneLinkHost = <int>[
    51, 19, 19, 49, 171, 241, 201, 186, 64, 117, 120, 48, 186, 192, 132, 189,
    39, 99, 68, 55, 45, 134, 155, 142,
  ];
  static const List<int> _webkit = <int>[118, 74, 74, 105, 255, 173, 144, 224];
  static const List<int> _safari = <int>[113, 66, 81, 115];
  static const List<int> _safariTail = <int>[118, 74, 75, 105, 255];
  static const List<int> _uaProduct = <int>[
    13, 21, 5, 46, 162, 239, 192, 250, 7, 50, 50,
  ];
  static const List<int> _uaPlatA = <int>[
    96, 82, 22, 23, 166, 236, 207, 176, 9, 60, 65, 15, 129, 206, 130, 131,
    42, 96, 67, 60, 102, 231, 165, 203,
  ];
  static const List<int> _uaPlatB = <int>[
    96, 22, 22, 44, 171, 163, 236, 180, 81, 60, 77, 12, 244, 182, 194, 243,
  ];
  static const List<int> _uaEngine = <int>[
    1, 10, 15, 43, 171, 212, 196, 183, 121, 117, 118, 112,
  ];
  static const List<int> _uaGecko = <int>[
    96, 82, 52, 15, 154, 206, 237, 249, 18, 112, 107, 52, 177, 206, 172, 182,
    33, 100, 66, 112, 102,
  ];
  static const List<int> _uaVer = <int>[
    22, 31, 13, 52, 167, 236, 207, 250,
  ];
  static const List<int> _uaMobile = <int>[
    96, 55, 16, 37, 167, 239, 196, 250, 3, 41, 71, 110, 224, 214, 203,
  ];
  static const List<int> _uaSafari = <int>[
    19, 27, 25, 38, 188, 234, 142,
  ];

  static String get endpoint => unfoldGleam(_endpoint);
  static String get appsFlyerKey => unfoldGleam(_appsFlyerKey);
  static String get firebaseProjectNumber => unfoldGleam(_firebaseProject);
  static String get gcdBase => unfoldGleam(_gcd);
  static String get oneLinkHost => unfoldGleam(_oneLinkHost);
  static String get webKitVersion => unfoldGleam(_webkit);
  static String get safariVersion => unfoldGleam(_safari);
  static String get safariTail => unfoldGleam(_safariTail);
  static String get uaProduct => unfoldGleam(_uaProduct);
  static String get uaPlatformPrefix => unfoldGleam(_uaPlatA);
  static String get uaPlatformSuffix => unfoldGleam(_uaPlatB);
  static String get uaEngine => unfoldGleam(_uaEngine);
  static String get uaGecko => unfoldGleam(_uaGecko);
  static String get uaVersionToken => unfoldGleam(_uaVer);
  static String get uaMobileToken => unfoldGleam(_uaMobile);
  static String get uaSafariToken => unfoldGleam(_uaSafari);

  static String get storeToken => 'id$iosStoreId';

  static bool get grayCredentialsReady =>
      endpoint.isNotEmpty &&
      appsFlyerKey.isNotEmpty &&
      firebaseProjectNumber.isNotEmpty;
}
