// ─── Fasting Session ─────────────────────────────────────────────────────────
//
// Represents one intermittent fasting window. A row with ended_at == null
// is the currently active fast; all others are history.

// ── Protocol ──────────────────────────────────────────────────────────────────

enum FastingProtocol {
  h16_8('16:8', 16),
  h18_6('18:6', 18),
  h20_4('20:4', 20),
  omad('OMAD', 24);

  const FastingProtocol(this.label, this.fastHours);

  final String label;
  final int fastHours;

  int get eatHours => 24 - fastHours;

  String get description {
    switch (this) {
      case FastingProtocol.omad:
        return 'One meal a day · 24h fast';
      default:
        return '${fastHours}h fast · ${eatHours}h eating window';
    }
  }

  static FastingProtocol fromLabel(String label) {
    return FastingProtocol.values.firstWhere(
      (p) => p.label == label,
      orElse: () => FastingProtocol.h16_8,
    );
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class FastingSession {
  final String id;
  final String userId;
  final FastingProtocol protocol;
  final DateTime startedAt;
  final DateTime targetEnd;
  final DateTime? endedAt;

  const FastingSession({
    required this.id,
    required this.userId,
    required this.protocol,
    required this.startedAt,
    required this.targetEnd,
    this.endedAt,
  });

  // ── State helpers ──────────────────────────────────────────────────────────

  bool get isActive => endedAt == null;

  /// True when the target end time has been reached (whether or not
  /// the user has tapped "End Fast" yet).
  bool get isGoalReached => DateTime.now().isAfter(targetEnd);

  /// Total planned duration.
  Duration get fastDuration => Duration(hours: protocol.fastHours);

  /// How much time has elapsed since the fast started (capped at goal).
  Duration get elapsed {
    final end = endedAt ?? DateTime.now();
    final e = end.difference(startedAt);
    return e > fastDuration ? fastDuration : e;
  }

  /// Time left until the fasting window closes (zero once goal is reached).
  Duration get remaining {
    if (!isActive) return Duration.zero;
    final r = targetEnd.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  /// 0.0 → 1.0 progress through the fasting window.
  double get progress {
    final total = fastDuration.inSeconds;
    if (total == 0) return 0;
    return (elapsed.inSeconds / total).clamp(0.0, 1.0);
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  factory FastingSession.fromMap(Map<String, dynamic> map) {
    return FastingSession(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      protocol: FastingProtocol.fromLabel(map['protocol'] as String),
      startedAt: DateTime.parse(map['started_at'] as String).toLocal(),
      targetEnd: DateTime.parse(map['target_end'] as String).toLocal(),
      endedAt: map['ended_at'] == null
          ? null
          : DateTime.parse(map['ended_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'protocol': protocol.label,
        'fast_hours': protocol.fastHours,
        'started_at': startedAt.toUtc().toIso8601String(),
        'target_end': targetEnd.toUtc().toIso8601String(),
      };
}
