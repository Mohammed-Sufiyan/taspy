import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/nfc_platform.dart';
import '../domain/nfc_models.dart';

enum ScanPhase { idle, starting, scanning, timedOut, failed }

/// State for the NFC compatibility test screen.
///
/// Scanning stays on after a detection so the user can tap the same card
/// several times; it stops on cancel, on [scanTimeout] without a tap, or when
/// NFC is switched off.
class CompatibilityController extends ChangeNotifier {
  CompatibilityController(
    this._platform, {
    this.scanTimeout = const Duration(seconds: 30),
    this.duplicateWindow = const Duration(seconds: 1),
  });

  final NfcPlatform _platform;
  final Duration scanTimeout;

  /// Android can deliver the same tap twice in quick succession; repeats of
  /// the same fingerprint from the same source within this window are ignored.
  final Duration duplicateWindow;

  StreamSubscription<NfcEvent>? _subscription;
  Timer? _timeout;
  int _sessionDetections = 0;
  bool _disposed = false;

  NfcStatus? status;
  String? statusError;
  ScanPhase phase = ScanPhase.idle;
  String? message;
  final List<TagReading> readings = [];

  bool get isScanning =>
      phase == ScanPhase.scanning || phase == ScanPhase.starting;

  /// Compares fingerprints of all readings. Only meaningful if every tap was
  /// the same physical card, which the UI tells the user.
  IdConsistency? get idConsistency {
    final ids = readings.map((r) => r.fingerprint).nonNulls.toList();
    if (ids.length < 2) return null;
    return IdConsistency(taps: ids.length, distinctIds: ids.toSet().length);
  }

  Future<void> init() async {
    _subscription = _platform.events.listen(_onEvent);
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    try {
      status = await _platform.getStatus();
      statusError = null;
    } catch (e) {
      statusError = 'Could not read NFC status: $e';
    }
    _notify();
  }

  Future<void> startScan() async {
    if (isScanning) return; // Never run two scans at once.
    phase = ScanPhase.starting;
    message = null;
    _notify();
    try {
      await _platform.startScan();
      phase = ScanPhase.scanning;
      _sessionDetections = 0;
      _armTimeout();
    } on NfcScanException catch (e) {
      phase = ScanPhase.failed;
      message = switch (e.code) {
        'unavailable' => 'This phone has no NFC hardware.',
        'disabled' => 'NFC is turned off. Turn it on, then try again.',
        _ => 'Could not start scanning (${e.code}).',
      };
    } catch (e) {
      phase = ScanPhase.failed;
      message = 'Could not start scanning: $e';
    }
    _notify();
  }

  Future<void> cancelScan() =>
      _stop(ScanPhase.idle, _sessionDetections > 0 ? null : 'Scan cancelled.');

  void clearReadings() {
    readings.clear();
    if (!isScanning) message = null;
    _notify();
  }

  Future<void> openSettings() => _platform.openSettings();

  Future<void> _stop(ScanPhase next, String? text) async {
    _timeout?.cancel();
    if (!isScanning) return;
    phase = next;
    message = text;
    _notify();
    try {
      await _platform.stopScan();
    } catch (_) {
      // The native side also stops reader mode when the activity pauses.
    }
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(scanTimeout, () {
      if (_sessionDetections == 0) {
        _stop(
          ScanPhase.timedOut,
          'No card detected in ${scanTimeout.inSeconds} seconds. '
          'Hold the card flat against the middle of the phone\'s back and try again.',
        );
      } else {
        _stop(ScanPhase.idle, 'Scanning stopped after a quiet period.');
      }
    });
  }

  void _onEvent(NfcEvent event) {
    switch (event) {
      case NfcStatusChanged(:final status):
        this.status = status;
        if (!status.enabled && isScanning) {
          _stop(ScanPhase.failed, 'NFC was turned off, so scanning stopped.');
        }
      case NfcTagDetected(:final reading):
        if (_isDuplicate(reading)) return;
        readings.insert(0, reading);
        if (reading.source == TagSource.foregroundScan) {
          _sessionDetections++;
          _armTimeout();
          message =
              'Card detected. Tap it again to check whether its ID stays the same.';
        } else {
          message =
              'Android delivered a card tap to the app: '
              '${reading.source.label.toLowerCase()}.';
        }
    }
    _notify();
  }

  bool _isDuplicate(TagReading r) {
    if (readings.isEmpty || r.fingerprint == null) return false;
    final last = readings.first;
    return last.fingerprint == r.fingerprint &&
        last.source == r.source &&
        r.at.difference(last.at).abs() < duplicateWindow;
  }

  /// Plain-text summary for sharing test results. Contains no card data.
  String report() {
    final b = StringBuffer('NFC PIN App - compatibility report\n');
    final s = status;
    if (s != null) {
      b.writeln(
        'Device: ${s.device}, Android ${s.androidVersion} (API ${s.sdkInt})',
      );
      b.writeln(
        'NFC hardware: ${s.hardware ? 'yes' : 'no'}, enabled: ${s.enabled ? 'yes' : 'no'}',
      );
    }
    final c = idConsistency;
    if (c != null) {
      b.writeln('ID check: ${c.taps} taps, ${c.distinctIds} distinct ID(s)');
    }
    for (final r in readings.reversed) {
      b.writeln(
        '- ${r.at.toIso8601String()} | ${r.source.label} | ${r.techs.join(', ')} | '
        'id ${r.fingerprint ?? 'none'} (${r.idLength} bytes'
        '${r.randomIdHint ? ', random-ID marker' : ''})'
        '${r.sak != null ? ' | SAK ${r.sak} ATQA ${r.atqa}' : ''}',
      );
    }
    return b.toString();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    _subscription?.cancel();
    if (isScanning) _platform.stopScan().ignore();
    super.dispose();
  }
}
