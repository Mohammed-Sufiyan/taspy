import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Smoothed phone tilt from the accelerometer, shared by every card shine.
/// Listens only while at least one widget is using it. No permission needed.
class DeviceTilt extends ValueNotifier<Offset> {
  DeviceTilt._() : super(Offset.zero);

  static final instance = DeviceTilt._();

  /// Tests and reduced-motion users can turn the sensor off entirely.
  static bool enabled = true;

  StreamSubscription<AccelerometerEvent>? _sub;
  int _users = 0;

  void acquire() {
    _users++;
    if (_users > 1 || !enabled) return;
    try {
      _sub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(_onEvent, onError: (_) {}, cancelOnError: true);
    } catch (_) {
      // No sensor (or no plugin, e.g. in tests): the shine just stays still.
    }
  }

  void release() {
    _users = (_users - 1).clamp(0, 1 << 30);
    if (_users == 0) {
      _sub?.cancel();
      _sub = null;
    }
  }

  void _onEvent(AccelerometerEvent e) {
    // x: left/right tilt, y: forward/back. ~9.8 is gravity; map to -1..1.
    final target = Offset(
      (-e.x / 6).clamp(-1.0, 1.0),
      ((e.y - 6) / 6).clamp(-1.0, 1.0),
    );
    final next = Offset.lerp(value, target, 0.15)!;
    if ((next - value).distance > 0.004) value = next;
  }
}
