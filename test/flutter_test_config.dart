import 'dart:async';

import 'package:nfcpin/shared/device_tilt.dart';

/// Runs before every test file: no accelerometer plugin exists in tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  DeviceTilt.enabled = false;
  await testMain();
}
