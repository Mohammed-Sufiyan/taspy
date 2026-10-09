import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../nfc/data/nfc_platform.dart';
import '../../nfc/domain/nfc_models.dart';
import '../domain/registered_card.dart';
import 'cards_controller.dart';

enum AddCardStep {
  checkingNfc,
  nfcUnavailable,
  waitingFirstTap,
  waitingConfirmTap,
  timedOut,
  noId,
  idChanged,
  alreadyRegistered,
  ready,
  saving,
}

/// Registration flow. A card is only accepted after two separate taps give
/// the same ID, which proves the app will be able to recognise it later.
class AddCardController extends ChangeNotifier {
  AddCardController(
    this._platform,
    this._cards, {
    this.scanTimeout = const Duration(seconds: 30),
  });

  final NfcPlatform _platform;
  final CardsController _cards;
  final Duration scanTimeout;

  /// A second detection this soon after the first is treated as the same
  /// touch, not a confirming tap.
  static const _minGapBetweenTaps = Duration(milliseconds: 700);

  StreamSubscription<NfcEvent>? _subscription;
  Timer? _timeout;
  bool _disposed = false;

  AddCardStep step = AddCardStep.checkingNfc;
  String? nfcProblem;
  TagReading? firstTap;
  RegisteredCard? existing;
  String? saveError;

  bool get isScanning =>
      step == AddCardStep.waitingFirstTap ||
      step == AddCardStep.waitingConfirmTap;

  /// Checks NFC and starts scanning. Safe to call again as a retry.
  Future<void> start() async {
    _subscription ??= _platform.events.listen(_onEvent);
    _set(AddCardStep.checkingNfc);
    try {
      final status = await _platform.getStatus();
      if (!status.hardware) {
        return _fail('This phone has no NFC, so cards cannot be registered.');
      }
      if (!status.enabled) {
        return _fail('NFC is turned off. Turn it on, then try again.');
      }
    } catch (e) {
      return _fail('Could not check NFC: $e');
    }
    await restart();
  }

  Future<void> restart() async {
    _timeout?.cancel();
    firstTap = null;
    existing = null;
    saveError = null;
    try {
      await _platform.startScan();
    } on NfcScanException catch (e) {
      return _fail(
        e.code == 'disabled'
            ? 'NFC is turned off. Turn it on, then try again.'
            : 'Could not start scanning (${e.code}).',
      );
    }
    _set(AddCardStep.waitingFirstTap);
    _armTimeout();
  }

  Future<void> openSettings() => _platform.openSettings();

  Future<RegisteredCard?> save({
    required String name,
    required String message,
    int style = 0,
  }) async {
    final tap = firstTap;
    if (step != AddCardStep.ready || tap == null) return null;
    saveError = null;
    _set(AddCardStep.saving);
    try {
      return await _cards.add(
        name: name,
        message: message,
        fingerprint: tap.fingerprint!,
        category: tap.category,
        style: style,
      );
    } on CardRuleException catch (e) {
      saveError = e.message;
    } catch (e) {
      saveError = 'Could not save the card: $e';
    }
    _set(AddCardStep.ready);
    return null;
  }

  void _onEvent(NfcEvent event) {
    switch (event) {
      case NfcStatusChanged(:final status):
        if (!status.enabled && isScanning) {
          _stopScan();
          _fail('NFC was turned off. Turn it on, then try again.');
        }
      case NfcTagDetected(:final reading):
        if (reading.source == TagSource.foregroundScan) _onTap(reading);
    }
  }

  void _onTap(TagReading r) {
    switch (step) {
      case AddCardStep.waitingFirstTap:
        final fingerprint = r.fingerprint;
        if (fingerprint == null) return _finish(AddCardStep.noId);
        final match = _cards.byFingerprint(fingerprint);
        if (match != null) {
          existing = match;
          return _finish(AddCardStep.alreadyRegistered);
        }
        firstTap = r;
        _set(AddCardStep.waitingConfirmTap);
        _armTimeout();
      case AddCardStep.waitingConfirmTap:
        final first = firstTap!;
        if (r.at.difference(first.at).abs() < _minGapBetweenTaps) return;
        _finish(
          r.fingerprint == first.fingerprint
              ? AddCardStep.ready
              : AddCardStep.idChanged,
        );
      default:
        break;
    }
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(scanTimeout, () => _finish(AddCardStep.timedOut));
  }

  void _finish(AddCardStep next) {
    _stopScan();
    _set(next);
  }

  void _fail(String problem) {
    nfcProblem = problem;
    _set(AddCardStep.nfcUnavailable);
  }

  void _stopScan() {
    _timeout?.cancel();
    if (isScanning) _platform.stopScan().catchError((_) {});
  }

  void _set(AddCardStep next) {
    step = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _stopScan();
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
