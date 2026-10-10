import 'dart:math';

/// Consecutive days on which a card was tapped at least once.
///
/// Kept on the card itself (not derived from the tap history, which is
/// capped), so long streaks survive. Days are calendar days in local time.
class Streak {
  const Streak({this.current = 0, this.best = 0, this.lastDay});

  factory Streak.fromJson(Map<String, Object?> json) => Streak(
    current: json['current'] as int? ?? 0,
    best: json['best'] as int? ?? 0,
    lastDay: switch (json['day']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );

  static const none = Streak();

  /// Streak lengths worth a celebration in the tap popup.
  static const milestones = {3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 365};

  /// Length of the run that ended on [lastDay].
  final int current;
  final int best;

  /// The last day with a tap (date only), or null if never tapped.
  final DateTime? lastDay;

  Map<String, Object?> toJson() => {
    'current': current,
    'best': best,
    if (lastDay case final d?) 'day': _dateString(d),
  };

  /// The streak as of [now]: still alive if the last tap was today or
  /// yesterday, otherwise broken (0).
  int activeOn(DateTime now) {
    final last = lastDay;
    if (last == null) return 0;
    final gap = daysBetween(last, now);
    return gap >= 0 && gap <= 1 ? current : 0;
  }

  bool tappedOn(DateTime day) =>
      lastDay != null && daysBetween(lastDay!, day) == 0;

  /// The streak after a tap at [at]. A second tap on the same day changes
  /// nothing; a tap that seems to be in the past (clock changed) is ignored.
  Streak tap(DateTime at) {
    final day = _dateOnly(at);
    final last = lastDay;
    if (last == null) {
      return Streak(current: 1, best: max(best, 1), lastDay: day);
    }
    final gap = daysBetween(last, day);
    if (gap <= 0) return this;
    final next = gap == 1 ? current + 1 : 1;
    return Streak(current: next, best: max(best, next), lastDay: day);
  }

  /// Whole calendar days from [a] to [b] (DST-safe).
  static int daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is Streak &&
      other.current == current &&
      other.best == best &&
      other.lastDay == lastDay;

  @override
  int get hashCode => Object.hash(current, best, lastDay);
}
