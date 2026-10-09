import 'package:flutter/services.dart';

import '../../features/cards/data/card_repository.dart';

/// Encrypts saved data with an AES-256-GCM key kept in the Android Keystore
/// (see `NfcBridge.kt`). Works in both the app and the tap popup engines.
class KeystoreCipher implements StorageCipher {
  static const _channel = MethodChannel('nfcpin/nfc');

  @override
  Future<String> encrypt(String plain) async =>
      (await _channel.invokeMethod<String>('encrypt', {'text': plain}))!;

  @override
  Future<String> decrypt(String data) async =>
      (await _channel.invokeMethod<String>('decrypt', {'data': data}))!;
}
