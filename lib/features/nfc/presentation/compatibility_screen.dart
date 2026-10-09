import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/nfc_models.dart';
import 'compatibility_controller.dart';

class CompatibilityScreen extends StatefulWidget {
  const CompatibilityScreen({super.key, required this.controller});

  final CompatibilityController controller;

  @override
  State<CompatibilityScreen> createState() => _CompatibilityScreenState();
}

class _CompatibilityScreenState extends State<CompatibilityScreen> {
  late final AppLifecycleListener _lifecycle;

  CompatibilityController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Picks up NFC being switched on/off in Settings while we were away.
    _lifecycle = AppLifecycleListener(onResume: _c.refreshStatus);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _c.report()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('NFC compatibility test'),
          actions: [
            IconButton(
              tooltip: 'Copy report',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _c.readings.isEmpty ? null : _copyReport,
            ),
            IconButton(
              tooltip: 'Clear results',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _c.readings.isEmpty ? null : _c.clearReadings,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _StatusCard(controller: _c),
            const SizedBox(height: 12),
            _ScanCard(controller: _c),
            if (_c.idConsistency case final c?) ...[
              const SizedBox(height: 12),
              _ConsistencyCard(result: c),
            ],
            const SizedBox(height: 12),
            if (_c.readings.isEmpty)
              const _BackgroundHint()
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(
                  'Detected taps (${_c.readings.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final r in _c.readings) _ReadingCard(reading: r),
              const SizedBox(height: 12),
              const _BackgroundHint(),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final CompatibilityController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final error = controller.statusError;
    final scheme = Theme.of(context).colorScheme;

    if (error != null) {
      return _InfoCard(
        icon: Icons.error_outline,
        color: scheme.error,
        title: 'NFC status unknown',
        body: error,
      );
    }
    if (status == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!status.hardware) {
      return _InfoCard(
        icon: Icons.portable_wifi_off,
        color: scheme.error,
        title: 'This phone has no NFC',
        body:
            '${status.device} does not report NFC hardware, so cards cannot be '
            'read on this device.',
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRow(label: 'NFC hardware', value: 'Available', ok: true),
            const SizedBox(height: 8),
            _StatusRow(
              label: 'NFC',
              value: status.enabled ? 'On' : 'Off',
              ok: status.enabled,
            ),
            const SizedBox(height: 8),
            Text(
              '${status.device} · Android ${status.androidVersion}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!status.enabled) ...[
              const SizedBox(height: 12),
              const Text('Turn on NFC to scan cards.'),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: controller.openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open NFC settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? scheme.primary : scheme.error,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.controller});

  final CompatibilityController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final status = c.status;
    final canScan = status != null && status.hardware && status.enabled;
    final theme = Theme.of(context);
    final failed = c.phase == ScanPhase.failed || c.phase == ScanPhase.timedOut;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.isScanning) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text('Scanning…', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Hold the card flat against the back of the phone, near the '
                'middle, for a second. Nothing is written to the card and no '
                'payment data is read.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: c.cancelScan,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop scanning'),
              ),
            ] else
              FilledButton.icon(
                onPressed: canScan ? c.startScan : null,
                icon: const Icon(Icons.nfc),
                label: const Text('Scan NFC card'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            if (c.message case final text?) ...[
              const SizedBox(height: 12),
              Text(
                text,
                style: failed
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.result});

  final IdConsistency result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _InfoCard(
      icon: result.isStable ? Icons.verified_outlined : Icons.shuffle,
      color: result.isStable ? scheme.primary : scheme.tertiary,
      title: result.isStable
          ? 'Same ID on all ${result.taps} taps'
          : '${result.distinctIds} different IDs across ${result.taps} taps',
      body: result.isStable
          ? 'This card gives a stable ID, so the app could recognise it '
                '(note: an ID alone is not proof of ownership; it can be copied).'
          : 'If all taps were the same card, it changes its ID each time and '
                'cannot be told apart from other cards by ID. Clear results '
                'before testing a different card.',
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.reading});

  final TagReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reading;
    final time = TimeOfDay.fromDateTime(r.at).format(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.source.isDispatch ? Icons.launch : Icons.nfc,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.source.label,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(time, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(r.category.title, style: theme.textTheme.titleMedium),
            Text(r.category.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in r.techs)
                  Chip(label: Text(t), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ID fingerprint: ${r.fingerprint ?? 'none'} '
              '(${r.idLength}-byte ID${r.randomIdHint ? ', marked as random' : ''})',
              style: theme.textTheme.bodySmall,
            ),
            if (r.sak != null)
              Text(
                'SAK ${r.sak} · ATQA ${r.atqa}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundHint extends StatelessWidget {
  const _BackgroundHint();

  @override
  Widget build(BuildContext context) {
    return const _InfoCard(
      icon: Icons.science_outlined,
      title: 'Background taps',
      body:
          'When not scanning, card taps go to the tap popup instead of this '
          'page. To test: press Home and tap a card. A popup should say '
          'whether the card is registered. If you see "No supported '
          'application for this NFC tag" instead, Android did not deliver the tap.',
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
