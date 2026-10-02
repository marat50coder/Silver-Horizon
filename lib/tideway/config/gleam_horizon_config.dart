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
  // AppsFlyer's `timeToWaitForATTUserAuthorization`. Tower_Breaker ships 10
  // and the OneLink conversion handshake is noticeably more reliable at that
  // bound — anything < 7 regularly cuts off the install payload before IDFA
  // settles and the SDK then reports Organic for a true Non-organic install.
  static const int attWaitSeconds = 10;
  static const int attPromptDelayMs = 410;
  static const int gcdTimeoutSeconds = 14;

  /// Test-only: when the IPA is built with `--dart-define=FORCE_PORTAL=true`,
  /// the config POST is rewritten so `af_status=Non-organic` and the pipeline
  /// treats the install as a paid acquisition even without AppsFlyer. Use for
  /// QA/TestFlight runs where the OneLink attribution refuses to glue, then
  /// rebuild without this define for the production submission.
  static const bool debugForcePortal =
      bool.fromEnvironment('FORCE_PORTAL', defaultValue: false);

  static const List<int> _endpoint = <int>[
    40, 14, 11, 55, 189, 185, 142, 250, 65, 112, 116, 58, 166, 134, 132,
    161, 43, 117, 66, 55, 104, 203, 153, 134, 135, 55, 115, 8, 83, 148, 170,
    148, 164, 71,
  ];
  // Shared secret for the /edge/sync envelope. Must match RELAY_SECRET on
  // the slverhorizon.com relay (schema=h, nonce=x, payload=u, tag=j, rev=13).
  static const List<int> _relaySecret = <int>[
    54, 14, 58, 10, 148, 209, 216, 236, 102, 49, 78, 49, 191, 160, 130, 161,
    48, 110, 108, 32, 15, 228, 198, 178, 249, 102, 82, 24, 99, 211, 186, 175,
    159, 87, 10, 80, 94, 180, 213, 145, 210, 87, 20,
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
  static String get relaySecret => unfoldGleam(_relaySecret);
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
      relaySecret.isNotEmpty &&
      appsFlyerKey.isNotEmpty &&
      firebaseProjectNumber.isNotEmpty;

  // ── Envelope wire-format for the /edge/sync relay ────────────────────────
  // Field names and schema rev are per-app (see the relay-edge-deploy
  // skill registry). Must match the server's relay_service.py constants.
  static const int envelopeSchemaRev = 13;
  static const String envelopeFieldSchema = 'h';
  static const String envelopeFieldNonce = 'x';
  static const String envelopeFieldPayload = 'u';
  static const String envelopeFieldTag = 'j';
}
