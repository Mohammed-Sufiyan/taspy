import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/motion.dart';
import '../../../shared/widgets/pop_button.dart';
import '../../nfc/data/nfc_platform.dart';
import '../domain/card_action.dart';
import 'action_tile.dart';

/// "When tapped" section of the add/edit card forms.
class ActionsEditor extends StatelessWidget {
  const ActionsEditor({
    super.key,
    required this.actions,
    required this.onChanged,
    required this.platform,
    this.enabled = true,
  });

  final List<CardAction> actions;
  final ValueChanged<List<CardAction>> onChanged;
  final NfcPlatform platform;
  final bool enabled;

  bool get _hasOpener => actions.any((a) => a.type.opensApp);

  Future<void> _add(BuildContext context) async {
    final type = await showModalBottomSheet<ActionType>(
      context: context,
      backgroundColor: TapsyColors.surface,
      showDragHandle: true,
      builder: (_) => _TypeSheet(hasOpener: _hasOpener),
    );
    if (type == null || !context.mounted) return;
    final action = await editCardAction(
      context,
      type,
      platform,
      others: actions,
    );
    if (action != null) {
      Haptics.success();
      onChanged([...actions, action]);
    }
  }

  Future<void> _edit(BuildContext context, CardAction current) async {
    final action = await editCardAction(
      context,
      current.type,
      platform,
      initial: current,
      others: [...actions]..remove(current),
    );
    if (action == null) return;
    final i = actions.indexOf(current);
    onChanged([...actions]..[i] = action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
      decoration: BoxDecoration(
        color: TapsyColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: actions.isEmpty
              ? TapsyColors.outline
              : TapsyColors.lime.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: TapsyColors.lime),
              const SizedBox(width: 8),
              Expanded(
                child: Text('When tapped', style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${actions.length}/${ActionRules.maxActions}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: TapsyColors.textFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              actions.isEmpty
                  ? 'Also open an app, call someone, turn on the flashlight…'
                  : 'Runs after the popup shows. Apps and links open last. '
                        'Tap an action to set when it runs.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 6),
          for (final a in ActionRules.runOrder(actions))
            ActionTile(
              key: ObjectKey(a),
              action: a,
              onTap: enabled ? () => _edit(context, a) : null,
              trailing: IconButton(
                tooltip: 'Remove action',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: enabled
                    ? () {
                        Haptics.detected();
                        onChanged([...actions]..remove(a));
                      }
                    : null,
              ),
            ),
          if (actions.length < ActionRules.maxActions)
            TextButton.icon(
              key: const ValueKey('add-action'),
              onPressed: enabled ? () => _add(context) : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add action'),
              style: TextButton.styleFrom(foregroundColor: TapsyColors.lime),
            ),
        ],
      ),
    );
  }
}

/// Grid of action types.
class _TypeSheet extends StatelessWidget {
  const _TypeSheet({required this.hasOpener});

  final bool hasOpener;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add an action', style: theme.textTheme.titleLarge),
            if (hasOpener)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This card already opens something. Another app, link, '
                  'call or chat needs a different time of day.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
              children: [
                for (final t in ActionType.values)
                  _TypeButton(type: t, enabled: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.type, required this.enabled});

  final ActionType type;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? TapsyColors.lime : TapsyColors.textFaint;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        key: ValueKey('type-${type.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? () => Navigator.of(context).pop(type) : null,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: TapsyColors.surfaceHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TapsyColors.outline),
              ),
              child: Icon(type.icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              type.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

Future<InstalledApp?> _pickApp(BuildContext context, NfcPlatform platform) =>
    Navigator.of(context).push<InstalledApp>(
      MaterialPageRoute(builder: (_) => AppPickerScreen(platform: platform)),
    );

/// Opens the right editor for [type]; returns the new action or null.
/// [others] are the card's other actions, checked for opener clashes.
Future<CardAction?> editCardAction(
  BuildContext context,
  ActionType type,
  NfcPlatform platform, {
  CardAction? initial,
  List<CardAction> others = const [],
}) async {
  var start = initial;
  if (type == ActionType.openApp && start == null) {
    // New "open an app": choose the app first, then when it runs.
    final app = await _pickApp(context, platform);
    if (app == null || !context.mounted) return null;
    start = CardAction(
      type: ActionType.openApp,
      value: app.packageName,
      label: app.label,
    );
  }
  return showModalBottomSheet<CardAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TapsyColors.surface,
    showDragHandle: true,
    builder: (_) => _ActionForm(
      type: type,
      initial: start,
      isNew: initial == null,
      others: others,
      platform: platform,
    ),
  );
}

class _ActionForm extends StatefulWidget {
  const _ActionForm({
    required this.type,
    required this.platform,
    required this.isNew,
    required this.others,
    this.initial,
  });

  final ActionType type;
  final NfcPlatform platform;
  final CardAction? initial;
  final bool isNew;
  final List<CardAction> others;

  @override
  State<_ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<_ActionForm> {
  final _formKey = GlobalKey<FormState>();
  late final _value = TextEditingController(text: widget.initial?.value);
  late final _label = TextEditingController(text: widget.initial?.label);
  late final _extra = TextEditingController(text: widget.initial?.extra);
  late FlashlightMode _flash =
      widget.initial?.flashlightMode ?? FlashlightMode.toggle;
  late ActionTime _time = widget.initial?.time ?? ActionTime.always;
  late ActionDays _days = widget.initial?.days ?? ActionDays.everyDay;
  String? _clash;

  /// The schedule chips start folded away unless they're needed.
  late bool _showWhen =
      (widget.initial?.isScheduled ?? false) ||
      (_type.opensApp && widget.others.any((o) => o.type.opensApp));

  ActionType get _type => widget.type;

  @override
  void initState() {
    super.initState();
    if (_type == ActionType.timer && _value.text.isEmpty) _value.text = '10';
  }

  @override
  void dispose() {
    _value.dispose();
    _label.dispose();
    _extra.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final contact = await widget.platform.pickContact();
    if (contact == null || !mounted) return;
    setState(() {
      _value.text = contact.phone;
      _label.text = contact.name;
    });
  }

  Future<void> _changeApp() async {
    final app = await _pickApp(context, widget.platform);
    if (app == null || !mounted) return;
    setState(() {
      _value.text = app.packageName;
      _label.text = app.label;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final action = CardAction(
      type: _type,
      value: switch (_type) {
        ActionType.openLink => ActionRules.normalizeLink(_value.text)!,
        ActionType.flashlight => _flash.name,
        _ => _value.text.trim(),
      },
      label: _label.text.trim(),
      extra: _extra.text.trim(),
      time: _time,
      days: _days,
    );
    if (ActionRules.openerClash(action, widget.others) != null) {
      Haptics.error();
      setState(() {
        _clash = ActionRules.clashMessage;
        _showWhen = true;
      });
      return;
    }
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = switch (_type) {
      ActionType.openApp => [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: TapsyColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TapsyColors.outline),
          ),
          child: Row(
            children: [
              const Icon(Icons.apps_rounded, color: TapsyColors.lime),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label.text.isEmpty ? _value.text : _label.text,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: _changeApp, child: const Text('Change')),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
      ActionType.openLink => [
        _field(
          _value,
          'Link',
          hint: 'e.g. youtube.com',
          keyboard: TextInputType.url,
          validator: ActionRules.link,
        ),
      ],
      ActionType.call || ActionType.whatsapp => [
        _field(
          _value,
          _type == ActionType.whatsapp
              ? 'Phone number with country code'
              : 'Phone number',
          hint: '+91 98765 43210',
          keyboard: TextInputType.phone,
          validator: _type == ActionType.whatsapp
              ? ActionRules.whatsappPhone
              : ActionRules.phone,
          suffix: IconButton(
            tooltip: 'Choose a contact',
            icon: const Icon(Icons.contacts_rounded),
            onPressed: _pickContact,
          ),
        ),
        _field(_label, 'Name (optional)', hint: 'e.g. Mom', max: 40),
        if (_type == ActionType.whatsapp)
          _field(
            _extra,
            'Message to type in (optional)',
            hint: 'You still press send',
            lines: 3,
            max: ActionRules.maxTextLength,
          ),
      ],
      ActionType.navigate => [
        _field(
          _value,
          'Where to?',
          hint: 'An address or place, e.g. Home',
          validator: (v) => ActionRules.text(v, max: 200),
          max: 200,
        ),
      ],
      ActionType.flashlight => [
        SegmentedButton<FlashlightMode>(
          segments: const [
            ButtonSegment(value: FlashlightMode.toggle, label: Text('Toggle')),
            ButtonSegment(value: FlashlightMode.on, label: Text('On')),
            ButtonSegment(value: FlashlightMode.off, label: Text('Off')),
          ],
          selected: {_flash},
          onSelectionChanged: (s) => setState(() => _flash = s.first),
        ),
      ],
      ActionType.copyText => [
        _field(
          _value,
          'Text to copy',
          hint: 'e.g. your UPI ID or Wi-Fi password',
          lines: 3,
          validator: ActionRules.text,
          max: ActionRules.maxTextLength,
        ),
      ],
      ActionType.timer => [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const [1, 5, 10, 15, 25, 30, 45, 60])
              ChoiceChip(
                label: Text('$m min'),
                selected: _value.text.trim() == '$m',
                onSelected: (_) => setState(() => _value.text = '$m'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          _value,
          'Minutes',
          keyboard: TextInputType.number,
          validator: ActionRules.minutes,
          onChanged: (_) => setState(() {}),
        ),
        _field(_label, 'Timer name (optional)', hint: 'e.g. Tea', max: 40),
      ],
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_type.icon, color: TapsyColors.lime),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _type.title,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_hint, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                ...fields,
                const SizedBox(height: 4),
                _whenPicker(theme),
                if (_clash case final clash?)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      clash,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: TapsyColors.danger,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                PopButton(
                  label: widget.isNew ? 'ADD ACTION' : 'SAVE ACTION',
                  icon: Icons.check_rounded,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _whenPicker(ThemeData theme) {
    final summary = CardAction(type: _type, time: _time, days: _days).whenLabel;
    if (!_showWhen) {
      return InkWell(
        key: const ValueKey('when-toggle'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _showWhen = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 18,
                color: TapsyColors.lime,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Runs ${summary ?? 'any time'}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                'Set a time',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: TapsyColors.lime,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 18,
              color: TapsyColors.lime,
            ),
            const SizedBox(width: 8),
            Text('When', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in ActionTime.values)
              ChoiceChip(
                key: ValueKey('time-${t.name}'),
                label: Text(
                  t.hours.isEmpty ? t.title : '${t.title} · ${t.hours}',
                ),
                selected: _time == t,
                onSelected: (_) => setState(() {
                  _time = t;
                  _clash = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ActionDays>(
            showSelectedIcon: false,
            segments: [
              for (final d in ActionDays.values)
                ButtonSegment(
                  value: d,
                  label: Text(d.title, key: ValueKey('days-${d.name}')),
                ),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() {
              _days = s.first;
              _clash = null;
            }),
          ),
        ),
      ],
    );
  }

  String get _hint => switch (_type) {
    ActionType.openApp =>
      'Opens the app. Pick a time to open different apps '
          'in the morning and at night.',
    ActionType.openLink => 'Opens in your browser or the matching app.',
    ActionType.call =>
      'Opens the dialer with the number filled in. You press call.',
    ActionType.whatsapp =>
      'Opens the chat in WhatsApp. Nothing is sent until you press send.',
    ActionType.navigate => 'Starts directions in Google Maps.',
    ActionType.flashlight =>
      'Switches the flashlight, no camera access needed.',
    ActionType.copyText => 'Copies the text so you can paste it anywhere.',
    ActionType.timer => 'Starts a timer in your Clock app.',
  };

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboard,
    FormFieldValidator<String>? validator,
    Widget? suffix,
    int lines = 1,
    int? max,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: lines > 1 ? TextInputType.multiline : keyboard,
        minLines: lines > 1 ? 2 : 1,
        maxLines: lines,
        maxLength: max,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
        validator: validator ?? (v) => ActionRules.text(v, required: false),
      ),
    );
  }
}

/// Searchable list of the phone's launcher apps.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key, required this.platform});

  final NfcPlatform platform;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  late final Future<List<InstalledApp>> _apps = widget.platform.listApps();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose an app')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _apps,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Couldn’t load your apps.'));
                }
                final apps = snapshot.data;
                if (apps == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = [
                  for (final a in apps)
                    if (_query.isEmpty ||
                        a.label.toLowerCase().contains(_query))
                      a,
                ];
                if (shown.isEmpty) {
                  return const Center(child: Text('No apps found.'));
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final app = shown[i];
                    return ListTile(
                      leading: SizedBox.square(
                        dimension: 40,
                        child: app.icon == null
                            ? const Icon(Icons.android_rounded)
                            : Image.memory(app.icon!, gaplessPlayback: true),
                      ),
                      title: Text(app.label),
                      onTap: () => Navigator.of(context).pop(app),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
