import '../../engine/engine.dart';

/// Maximum allowed undo actions per match.
enum UndoLimit {
  unlimited(label: '무제한', maxCount: null),
  three(label: '3회', maxCount: 3),
  one(label: '1회', maxCount: 1),
  none(label: '금지', maxCount: 0);

  const UndoLimit({
    required this.label,
    required this.maxCount,
  });

  final String label;

  /// `null` means unlimited; otherwise exact cap per match.
  final int? maxCount;
}

/// Configurable match rules independent of visual/convenience preferences.
class MatchRules {
  const MatchRules({
    this.ruleType = RuleType.renju,
    this.useTimeLimit = false,
    this.turnTimeLimitSeconds = 30,
    this.undoLimit = UndoLimit.unlimited,
  });

  static const int minTurnSeconds = 1;
  static const int maxTurnSeconds = 100;

  factory MatchRules.fromJson(Map<String, dynamic> json) {
    final ruleIdx = (json['ruleType'] as int? ?? 0)
        .clamp(0, RuleType.values.length - 1);
    final undoIdx = (json['undoLimit'] as int? ?? 0)
        .clamp(0, UndoLimit.values.length - 1);
    final seconds = (json['turnTimeLimitSeconds'] as int? ?? 30)
        .clamp(minTurnSeconds, maxTurnSeconds);

    return MatchRules(
      ruleType: RuleType.values[ruleIdx],
      useTimeLimit: json['useTimeLimit'] as bool? ?? false,
      turnTimeLimitSeconds: seconds,
      undoLimit: UndoLimit.values[undoIdx],
    );
  }

  final RuleType ruleType;

  /// Applies per-turn countdown timer equally to both human and AI turns.
  final bool useTimeLimit;

  /// Per-turn time budget in seconds (`1..100`).
  final int turnTimeLimitSeconds;

  /// Maximum undos allowed per match.
  final UndoLimit undoLimit;

  RuleEngine createRuleEngine() => ruleType == RuleType.freestyle
      ? const FreestyleRuleEngine()
      : const RenjuRuleEngine();

  MatchRules copyWith({
    RuleType? ruleType,
    bool? useTimeLimit,
    int? turnTimeLimitSeconds,
    UndoLimit? undoLimit,
  }) =>
      MatchRules(
        ruleType: ruleType ?? this.ruleType,
        useTimeLimit: useTimeLimit ?? this.useTimeLimit,
        turnTimeLimitSeconds: (turnTimeLimitSeconds ?? this.turnTimeLimitSeconds)
            .clamp(minTurnSeconds, maxTurnSeconds),
        undoLimit: undoLimit ?? this.undoLimit,
      );

  Map<String, dynamic> toJson() => {
        'ruleType': ruleType.index,
        'useTimeLimit': useTimeLimit,
        'turnTimeLimitSeconds': turnTimeLimitSeconds,
        'undoLimit': undoLimit.index,
      };
}
