/// Where a card reading came from.
///
/// Only [foregroundScan] happens while the app is actively scanning. The other
/// sources mean Android itself dispatched the tap to the app, which is what the
/// background automation depends on.
enum TagSource {
  foregroundScan('Foreground scan'),
  launchedFromClosed('Card tap opened the app (app was closed)'),
  launchedFromBackground('Card tap brought the app to front'),
  tappedWhileOpen('Card tapped while app open, not scanning');

  const TagSource(this.label);

  final String label;

  bool get isDispatch => this != foregroundScan;

  static TagSource fromWire(String? value) => switch (value) {
    'foreground_scan' => foregroundScan,
    'launch_closed' => launchedFromClosed,
    'launch_background' => launchedFromBackground,
    _ => tappedWhileOpen,
  };
}

class NfcStatus {
  const NfcStatus({
    required this.hardware,
    required this.enabled,
    required this.device,
    required this.androidVersion,
    required this.sdkInt,
  });

  factory NfcStatus.fromMap(Map<Object?, Object?> map) => NfcStatus(
    hardware: map['hardware'] == true,
    enabled: map['enabled'] == true,
    device: map['device'] as String? ?? 'Unknown device',
    androidVersion: map['androidVersion'] as String? ?? '?',
    sdkInt: map['sdkInt'] as int? ?? 0,
  );

  final bool hardware;
  final bool enabled;
  final String device;
  final String androidVersion;
  final int sdkInt;
}

enum CardCategory {
  ndefTag(
    'NDEF tag',
    'Ordinary NFC tag with NDEF data. Best fit for automations.',
  ),
  smartCard(
    'Smart card (ISO-DEP)',
    'Typical of bank/credit cards. No NDEF data, so it can only be matched by its ID.',
  ),
  otherTag('Other NFC tag', 'Basic tag without NDEF or ISO-DEP.');

  const CardCategory(this.title, this.description);

  final String title;
  final String description;
}

/// One detected tap. Contains no card data: [fingerprint] is a salted,
/// truncated hash of the tag ID computed natively, used only to compare taps.
class TagReading {
  const TagReading({
    required this.source,
    required this.techs,
    required this.fingerprint,
    required this.idLength,
    required this.randomIdHint,
    required this.at,
    this.atqa,
    this.sak,
  });

  factory TagReading.fromMap(Map<Object?, Object?> map) => TagReading(
    source: TagSource.fromWire(map['source'] as String?),
    techs: (map['techs'] as List<Object?>? ?? const []).cast<String>(),
    fingerprint: map['fingerprint'] as String?,
    idLength: map['idLength'] as int? ?? 0,
    randomIdHint: map['randomIdHint'] == true,
    atqa: map['atqa'] as String?,
    sak: map['sak'] as int?,
    at: DateTime.fromMillisecondsSinceEpoch(map['timestampMs'] as int? ?? 0),
  );

  final TagSource source;
  final List<String> techs;
  final String? fingerprint;
  final int idLength;

  /// True when the ID is a 4-byte NFC-A ID starting with 0x08, which the
  /// ISO 14443-3 standard reserves for randomly generated IDs.
  final bool randomIdHint;
  final String? atqa;
  final int? sak;
  final DateTime at;

  CardCategory get category {
    if (techs.contains('Ndef')) return CardCategory.ndefTag;
    if (techs.contains('IsoDep')) return CardCategory.smartCard;
    return CardCategory.otherTag;
  }
}

/// Result of comparing fingerprints across taps of what the user says is one card.
class IdConsistency {
  const IdConsistency({required this.taps, required this.distinctIds});

  final int taps;
  final int distinctIds;

  bool get isStable => distinctIds == 1;
}
