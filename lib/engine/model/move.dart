import 'coordinate.dart';
import 'stone.dart';

/// Immutable record of a single move played on the board.
class Move {
  const Move({
    required this.coordinate,
    required this.stone,
    required this.moveNumber,
  });

  final Coordinate coordinate;
  final Stone stone;

  /// 1-based ply count (1 = Black's opening move).
  final int moveNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Move &&
          coordinate == other.coordinate &&
          stone == other.stone &&
          moveNumber == other.moveNumber;

  @override
  int get hashCode => Object.hash(coordinate, stone, moveNumber);

  @override
  String toString() =>
      'Move(#$moveNumber ${stone.name} @ ${coordinate.notation})';
}
