import 'package:flutter/material.dart';

/// What a card can do when tapped, besides showing its message.
enum ActionType {
  openApp('Open an app', Icons.apps_rounded),
  openLink('Open a link', Icons.link_rounded),
  call('Call someone', Icons.call_rounded),
  whatsapp('WhatsApp someone', Icons.chat_rounded),
  navigate('Navigate', Icons.directions_rounded),
  flashlight('Flashlight', Icons.flashlight_on_rounded),
  copyText('Copy text', Icons.content_copy_rounded),
  timer('Start a timer', Icons.timer_outlined);

  const ActionType(this.title, this.icon);

  final String title;
  final IconData icon;

  /// Brings another app to the front, which ends the tap popup. A card can
  /// have only one, and it always runs last: once another app is in front,
  /// Android doesn't let Tapsy start anything else.
  bool get opensApp => switch (this) {
    openApp || openLink || call || whatsapp || navigate => true,
    flashlight || copyText || timer => false,
  };
}

enum FlashlightMode { toggle, on, off }

/// Part of the day an action runs in. Hours are local, [start] inclusive,
/// [end] exclusive; [night] wraps past midnight.
enum ActionTime {
  always('Any time', '', 0, 24),
  morning('Mornings', '5am–12pm', 5, 12),
  afternoon('Afternoons', '12–5pm', 12, 17),
  evening('Evenings', '5–9pm', 17, 21),
  night('Nights', '9pm–5am', 21, 5);

  const ActionTime(this.title, this.hours, this.start, this.end);

  final String title;
  final String hours;
  final int start;
  final int end;

  bool contains(int hour) =>
      start <= end ? hour >= start && hour < end : hour >= start || hour < end;

  bool overlaps(ActionTime other) =>
      this == always || other == always || this == other;
}

/// Days of the week an action runs on.
enum ActionDays {
  everyDay('Every day'),
  weekdays('Weekdays'),
  weekends('Weekends');

  const ActionDays(this.title);

  final String title;

  bool contains(int weekday) => switch (this) {
    everyDay => true,
    weekdays => weekday <= DateTime.friday,
    weekends => weekday >= DateTime.saturday,
  };

  bool overlaps(ActionDays other) =>
      this == everyDay || other == everyDay || this == other;
}

/// One configured action. Fields by type:
///
/// | type       | value              | label        | extra    |
/// |------------|--------------------|--------------|----------|
/// | openApp    | package name       | app name     |          |
/// | openLink   | https URL          |              |          |
/// | call       | phone number       | contact name |          |
/// | whatsapp   | phone (with code)  | contact name | message  |
/// | navigate   | destination        |              |          |
/// | flashlight | toggle / on / off  |              |          |
/// | copyText   | text               |              |          |
/// | timer      | minutes            | timer name   |          |
///
/// [time] and [days] limit when the action runs (default: always), so one
/// card can do different things in the morning and at night.
///
/// Stored inside the encrypted cards file; nothing here is sent anywhere.
class CardAction {
  const CardAction({
    required this.type,
    this.value = '',
    this.label = '',
    this.extra = '',
    this.time = ActionTime.always,
    this.days = ActionDays.everyDay,
  });

  factory CardAction.fromJson(Map<String, Object?> json) => CardAction(
    type: ActionType.values.byName(json['type']! as String),
    value: json['value'] as String? ?? '',
    label: json['label'] as String? ?? '',
    extra: json['extra'] as String? ?? '',
    time: ActionTime.values.asNameMap()[json['time']] ?? ActionTime.always,
    days: ActionDays.values.asNameMap()[json['days']] ?? ActionDays.everyDay,
  );

  final ActionType type;
  final String value;
  final String label;
  final String extra;
  final ActionTime time;
  final ActionDays days;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'value': value,
    if (label.isNotEmpty) 'label': label,
    if (extra.isNotEmpty) 'extra': extra,
    if (time != ActionTime.always) 'time': time.name,
    if (days != ActionDays.everyDay) 'days': days.name,
  };

  CardAction copyWith({ActionTime? time, ActionDays? days}) => CardAction(
    type: type,
    value: value,
    label: label,
    extra: extra,
    time: time ?? this.time,
    days: days ?? this.days,
  );

  bool get isScheduled =>
      time != ActionTime.always || days != ActionDays.everyDay;

  bool runsAt(DateTime t) => time.contains(t.hour) && days.contains(t.weekday);

  /// True if both could run on the same tap.
  bool overlaps(CardAction other) =>
      time.overlaps(other.time) && days.overlaps(other.days);

  /// e.g. "Mornings · weekdays", or null when it always runs.
  String? get whenLabel {
    if (!isScheduled) return null;
    final parts = [
      if (time != ActionTime.always) time.title,
      if (days != ActionDays.everyDay)
        time == ActionTime.always ? days.title : days.title.toLowerCase(),
    ];
    return parts.join(' · ');
  }

  /// Short line shown in lists, e.g. "Open Spotify" or "10-min timer".
  String get title => switch (type) {
    ActionType.openApp => 'Open ${label.isEmpty ? value : label}',
    ActionType.openLink => 'Open ${Uri.tryParse(value)?.host ?? value}',
    ActionType.call => 'Call ${label.isEmpty ? value : label}',
    ActionType.whatsapp => 'WhatsApp ${label.isEmpty ? value : label}',
    ActionType.navigate => 'Navigate to $value',
    ActionType.flashlight => switch (flashlightMode) {
      FlashlightMode.toggle => 'Toggle flashlight',
      FlashlightMode.on => 'Flashlight on',
      FlashlightMode.off => 'Flashlight off',
    },
    ActionType.copyText => 'Copy text',
    ActionType.timer =>
      label.isEmpty ? '$minutes-min timer' : '$minutes-min timer · $label',
  };

  /// Second line with the detail, or null.
  String? get subtitle => switch (type) {
    ActionType.openLink => value,
    ActionType.call || ActionType.whatsapp when label.isNotEmpty =>
      extra.isEmpty ? value : '$value · “$extra”',
    ActionType.whatsapp when extra.isNotEmpty => '“$extra”',
    ActionType.copyText => value,
    _ => null,
  };

  FlashlightMode get flashlightMode =>
      FlashlightMode.values.asNameMap()[value] ?? FlashlightMode.toggle;

  int get minutes => int.tryParse(value) ?? 0;

  @override
  bool operator ==(Object other) =>
      other is CardAction &&
      other.type == type &&
      other.value == value &&
      other.label == label &&
      other.extra == extra &&
      other.time == time &&
      other.days == days;

  @override
  int get hashCode => Object.hash(type, value, label, extra, time, days);
}

/// Input rules for actions, shared by the editor and the controller.
abstract final class ActionRules {
  static const maxActions = 8;
  static const maxTextLength = 500;
  static const maxMinutes = 1440;

  /// Order actions run in: quick ones first, then the one that opens an app.
  static List<CardAction> runOrder(List<CardAction> actions) => [
    ...actions.where((a) => !a.type.opensApp),
    ...actions.where((a) => a.type.opensApp),
  ];

  /// The actions that run on a tap at [now].
  static List<CardAction> activeAt(List<CardAction> actions, DateTime now) =>
      actions.where((a) => a.runsAt(now)).toList();

  /// An action that opens something and would run on the same tap as
  /// [action], or null. Only one app can be opened per tap.
  static CardAction? openerClash(
    CardAction action,
    Iterable<CardAction> others,
  ) {
    if (!action.type.opensApp) return null;
    for (final o in others) {
      if (o.type.opensApp && o.overlaps(action)) return o;
    }
    return null;
  }

  static const clashMessage =
      'Only one app, link, call or chat can open per tap. '
      'Give this one a different time.';

  /// Problem with the whole list, or null.
  static String? list(List<CardAction> actions) {
    if (actions.length > maxActions) {
      return 'A card can have up to $maxActions actions';
    }
    for (var i = 0; i < actions.length; i++) {
      if (openerClash(actions[i], actions.skip(i + 1)) != null) {
        return clashMessage;
      }
    }
    for (final a in actions) {
      if (validate(a) case final error?) return error;
    }
    return null;
  }

  static String? validate(CardAction a) => switch (a.type) {
    ActionType.openApp => a.value.isEmpty ? 'Choose an app' : null,
    ActionType.openLink => link(a.value),
    ActionType.call => phone(a.value),
    ActionType.whatsapp =>
      whatsappPhone(a.value) ?? text(a.extra, required: false),
    ActionType.navigate => text(a.value, max: 200),
    ActionType.flashlight => null,
    ActionType.copyText => text(a.value),
    ActionType.timer => minutes(a.value) ?? text(a.label, required: false),
  };

  /// Adds `https://` when no scheme is typed. Returns null if unusable.
  static String? normalizeLink(String input) {
    var v = input.trim();
    if (v.isEmpty) return null;
    if (!v.contains('://')) v = 'https://$v';
    return v;
  }

  static String? link(String? value) {
    final v = normalizeLink(value ?? '');
    if (v == null) return 'Enter a link';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.scheme != 'https') {
      return 'Only secure https:// links can be opened';
    }
    if (!uri.host.contains('.') || uri.host.startsWith('.')) {
      return 'Enter a valid web address';
    }
    return null;
  }

  static String digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a phone number';
    if (!RegExp(r'^\+?[\d\s\-()]+$').hasMatch(v)) {
      return 'Use digits only (and + for the country code)';
    }
    final n = digits(v).length;
    if (n < 3 || n > 15) return 'Enter a valid phone number';
    return null;
  }

  /// WhatsApp links need the full international number.
  static String? whatsappPhone(String? value) {
    final error = phone(value);
    if (error != null) return error;
    final n = digits(value!).length;
    if (n < 11) return 'Add the country code, e.g. +91 98765 43210';
    return null;
  }

  static String? minutes(String? value) {
    final m = int.tryParse(value?.trim() ?? '');
    if (m == null || m < 1 || m > maxMinutes) {
      return 'Enter 1 to $maxMinutes minutes';
    }
    return null;
  }

  static String? text(
    String? value, {
    bool required = true,
    int max = maxTextLength,
  }) {
    final v = value?.trim() ?? '';
    if (required && v.isEmpty) return 'This can’t be empty';
    if (v.length > max) return 'Keep it under $max characters';
    return null;
  }
}
