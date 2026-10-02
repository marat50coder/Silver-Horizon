enum TideRoute {
  native,
  portal,
  undecided;

  String get storageValue => switch (this) {
    TideRoute.native => 'shore',
    TideRoute.portal => 'gleam',
    TideRoute.undecided => 'pending',
  };

  static TideRoute parse(String? value) => switch (value) {
    'gleam' || 'portal' || 'web' => TideRoute.portal,
    'shore' || 'native' || 'game' => TideRoute.native,
    _ => TideRoute.undecided,
  };
}

class GleamReply {
  const GleamReply({
    required this.accepted,
    this.url,
    this.expiresAt,
    this.reason,
  });

  factory GleamReply.fromJson(Map<String, dynamic> json) {
    final rawExpiry = json['expires'];
    return GleamReply(
      accepted: json['ok'] == true,
      url: json['url'] is String ? json['url'] as String : null,
      expiresAt: rawExpiry is num
          ? rawExpiry.toInt()
          : int.tryParse(rawExpiry?.toString() ?? ''),
      reason: json['message']?.toString(),
    );
  }

  factory GleamReply.rejected(String reason) =>
      GleamReply(accepted: false, reason: reason);

  final bool accepted;
  final String? url;
  final int? expiresAt;
  final String? reason;

  bool get hasDestination => accepted && (url?.isNotEmpty ?? false);
}

sealed class TideDestination {
  const TideDestination();
}

final class NativeTide extends TideDestination {
  const NativeTide();
}

final class PortalTide extends TideDestination {
  const PortalTide(this.url, {this.coldLaunch = false});

  final String url;
  final bool coldLaunch;
}

final class OfflineTide extends TideDestination {
  const OfflineTide({required this.returnToNative});

  final bool returnToNative;
}
