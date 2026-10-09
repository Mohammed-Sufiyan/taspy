import 'package:flutter/material.dart';

import '../nfc/data/nfc_platform.dart';
import '../nfc/domain/nfc_models.dart';
import '../nfc/presentation/compatibility_controller.dart';
import '../nfc/presentation/compatibility_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.platform});

  final NfcPlatform platform;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppLifecycleListener _lifecycle;
  NfcStatus? _status;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.platform.getStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          section('NFC'),
          ListTile(
            leading: const Icon(Icons.nfc),
            title: const Text('NFC status'),
            subtitle: Text(
              s == null
                  ? 'Checking…'
                  : !s.hardware
                  ? 'Not available on this phone'
                  : s.enabled
                  ? 'On'
                  : 'Off',
            ),
            trailing: s != null && s.hardware
                ? TextButton(
                    onPressed: widget.platform.openSettings,
                    child: const Text('Open'),
                  )
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Device'),
            subtitle: Text(
              s == null
                  ? '…'
                  : '${s.device} · Android ${s.androidVersion} (API ${s.sdkInt})',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Card diagnostics'),
            subtitle: const Text(
              'Check what a card reports and whether its ID is stable',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _DiagnosticsPage(platform: widget.platform),
              ),
            ),
          ),
          section('How taps work'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('When the popup appears'),
            subtitle: Text(
              'Android shows your popup when a registered card is tapped while '
              'the phone is unlocked and NFC is on, even if this app is closed. '
              'Android does not read cards when the screen is off.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_none),
            title: Text('Notifications'),
            subtitle: Text(
              'Not used. Taps show a popup over the screen instead, so no '
              'notification permission is needed.',
            ),
          ),
          section('Privacy'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('What is stored'),
            subtitle: Text(
              'Only the card name, your message, on/off state, dates, and a '
              'scrambled code made from the card ID. The code is useless on '
              'any other phone or install.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.block),
            title: Text('What is never read or stored'),
            subtitle: Text(
              'Card numbers, expiry dates, CVV, PINs or any payment data. The '
              'app sends no commands to the card and never writes to it. '
              'Nothing leaves your phone.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.warning_amber_outlined),
            title: Text('Limits'),
            subtitle: Text(
              'A card ID can be copied, so a match is not proof the card is '
              "genuine. Don't use this to protect anything sensitive.",
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Owns the diagnostics controller so its scan stops when the page closes.
class _DiagnosticsPage extends StatefulWidget {
  const _DiagnosticsPage({required this.platform});

  final NfcPlatform platform;

  @override
  State<_DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<_DiagnosticsPage> {
  late final _controller = CompatibilityController(widget.platform)..init();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CompatibilityScreen(controller: _controller);
}
