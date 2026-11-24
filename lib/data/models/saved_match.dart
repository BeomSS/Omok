import '../../engine/engine.dart';
import 'match_rules.dart';

/// User's chosen stone color preference when starting a match.
enum StonePreference {
  black,
  white,
  random;

  String get label => switch (this) {
        StonePreference.black => '흑돌',
        StonePreference.white => '백돌',
        StonePreference.random => '무작위',
      };
}

/// Serializable snapshot of an unfinished match for offline resume ("이어하기").
class SavedMatch {
  const SavedMatch({
    required this.difficulty,
    required this.humanStone,
    required this.moveIndices,
    required this.updatedAtIso,
    this.stonePreference = StonePreference.black,
    this.rules = const MatchRules(),
    this.undosUsed = 0,
  });

  factory SavedMatch.fromJson(Map<String, dynamic> json) {
    final diffIdx = (json['difficulty'] as int? ?? 1)
        .clamp(0, AiDifficulty.values.length - 1);
    final stoneCode = json['humanStone'] as int? ?? Stone.black.code;
    final resolvedStone =
        stoneCode == Stone.white.code ? Stone.white : Stone.black;
    final prefIdx = json['stonePreference'] as int?;
    final preference = prefIdx != null &&
            prefIdx >= 0 &&
            prefIdx < StonePreference.values.length
        ? StonePreference.values[prefIdx]
        : (resolvedStone == Stone.white
            ? StonePreference.white
            : StonePreference.black);
    final rawMoves = (json['moves'] as List<dynamic>? ?? const [])
        .map((e) => e as int)
        .toList(growable: false);
    final rawRules = json['rules'];
    final rules = rawRules is Map<String, dynamic>
        ? MatchRules.fromJson(rawRules)
        : const MatchRules();

    return SavedMatch(
      difficulty: AiDifficulty.values[diffIdx],
      humanStone: resolvedStone,
      stonePreference: preference,
      rules: rules,
      undosUsed: json['undosUsed'] as int? ?? 0,
      moveIndices: rawMoves,
      updatedAtIso:
          json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  final AiDifficulty difficulty;
  final Stone humanStone;
  final StonePreference stonePreference;
  final MatchRules rules;
  final int undosUsed;
  final List<int> moveIndices;
  final String updatedAtIso;

  int get moveCount => moveIndices.length;

  /// Replays stored flat indices into an immutable [BoardState].
  BoardState toBoardState() {
    final coords = moveIndices.map(Coordinate.fromIndex);
    return BoardState.fromCoordinates(coords);
  }

  Map<String, dynamic> toJson() => {
        'difficulty': difficulty.index,
        'humanStone': humanStone.code,
        'stonePreference': stonePreference.index,
        'rules': rules.toJson(),
        'undosUsed': undosUsed,
        'moves': moveIndices,
        'updatedAt': updatedAtIso,
      };
}
