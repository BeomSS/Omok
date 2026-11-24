/// Standard 15x15 Omok / Renju board dimension.
const int kBoardSize = 15;
const int kBoardCellCount = kBoardSize * kBoardSize;

/// Immutable coordinate on a 15x15 Omok board (0-indexed).
class Coordinate {
  const Coordinate(this.row, this.col);

  factory Coordinate.fromIndex(int index) =>
      Coordinate(index ~/ kBoardSize, index % kBoardSize);

  final int row;
  final int col;

  /// Flat array index in [0, 224].
  int get index => row * kBoardSize + col;

  /// Whether this coordinate lies within the 15x15 board boundaries.
  bool get isValid =>
      row >= 0 && row < kBoardSize && col >= 0 && col < kBoardSize;

  /// Standard Renju algebraic notation (e.g., center (7,7) -> "H8").
  String get notation {
    final colChar = String.fromCharCode('A'.codeUnitAt(0) + col);
    final rowNumber = kBoardSize - row;
    return '$colChar$rowNumber';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coordinate && row == other.row && col == other.col;

  @override
  int get hashCode => row * kBoardSize + col;

  @override
  String toString() => 'Coordinate($row, $col [$notation])';
}
