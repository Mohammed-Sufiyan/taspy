import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// True when the user turned on Android's "Remove animations". Looping and
/// decorative animations should stop and transitions should be instant.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Haptic feedback for key moments. No permission needed: uses the view's
/// built-in haptics, which also respect the user's system vibration setting.
abstract final class Haptics {
  static Future<void> detected() => HapticFeedback.selectionClick();
  static Future<void> success() => HapticFeedback.mediumImpact();
  static Future<void> celebrate() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.lightImpact();
  }

  static Future<void> error() async {
    await HapticFeedback.vibrate();
  }
}
