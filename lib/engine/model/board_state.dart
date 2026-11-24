import 'dart:typed_data';

import 'coordinate.dart';
import 'move.dart';
import 'stone.dart';

/// Immutable snapshot of a 15x15 Omok board and its move history.
///
/// Backed internally by a flat [Uint8List] of length 225 for compact memory
/// layout and fast copying into background AI isolates.
class BoardState {
  BoardState._(this._cells, List<Move> history)
      : _history = List.unmodifiable(history);

  factory BoardState.empty() => BoardState._(
        Uint8List(kBoardCellCount),
        const [],
      );

  /// Reconstructs a board by replaying a sequence of coordinates (Black first).
  factory BoardState.fromCoordinates(Iterable<Coordinate> coords) {
    var board = BoardState.empty();
    for (final coord in coords) {
      board = board.placeStone(coord);
    }
    return board;
  }

  final Uint8List _cells;
  final List<Move> _history;

  /// Unmodifiable list of all moves played so far, in order.
  List<Move> get history => _history;

  /// Number of stones currently on the board.
  int get moveCount => _history.length;

  /// Whether all 225 intersections are occupied.
  bool get isFull => _history.length >= kBoardCellCount;

  /// Whether the board has no stones yet.
  bool get isEmpty => _history.isEmpty;

  /// Whether at least one stone has been placed on the board.
  bool get isNotEmpty => _history.isNotEmpty;

  /// Most recently played move, or `null` on an empty board.
  Move? get lastMove => _history.isEmpty ? null : _history.last;

  /// The player whose turn it is next (Black always moves first in Renju).
  Stone get nextTurn => _history.length.isEven ? Stone.black : Stone.white;

  /// Returns the stone at [coord], or [Stone.empty] if unoccupied.
  Stone stoneAt(Coordinate coord) {
    if (!coord.isValid) {
      throw RangeError('Coordinate out of bounds: $coord');
    }
    return Stone.fromCode(_cells[coord.index]);
  }

  /// Fast raw lookup by row and column.
  Stone stoneAtRowCol(int row, int col) {
    if (row < 0 || row >= kBoardSize || col < 0 || col >= kBoardSize) {
      throw RangeError('Row/col out of bounds: ($row, $col)');
    }
    return Stone.fromCode(_cells[row * kBoardSize + col]);
  }

  bool isOccupied(Coordinate coord) => stoneAt(coord) != Stone.empty;

  /// Returns a writable copy of the raw 225-byte cell buffer for fast rule
  /// evaluation and AI search without mutating this [BoardState].
  Uint8List copyRawCells() => Uint8List.fromList(_cells);

  /// Returns a new [BoardState] with [stone] (defaults to [nextTurn]) placed
  /// at [coord]. Throws [StateError] if [coord] is invalid or occupied.
  BoardState placeStone(Coordinate coord, {Stone? stone}) {
    if (!coord.isValid) {
      throw RangeError('Coordinate out of bounds: $coord');
    }
    final activeStone = stone ?? nextTurn;
    if (activeStone == Stone.empty) {
      throw ArgumentError('Cannot place Stone.empty on the board.');
    }
    if (_cells[coord.index] != Stone.empty.code) {
      throw StateError('Cell $coord is already occupied.');
    }

    final nextCells = Uint8List.fromList(_cells);
    nextCells[coord.index] = activeStone.code;
    final nextMove = Move(
      coordinate: coord,
      stone: activeStone,
      moveNumber: _history.length + 1,
    );
    return BoardState._(
      nextCells,
      [..._history, nextMove],
    );
  }

  /// Returns a new [BoardState] with the last [steps] moves undone.
  BoardState undo({int steps = 1}) {
    if (steps <= 0 || _history.isEmpty) {
      return this;
    }
    final removeCount = steps > _history.length ? _history.length : steps;
    final nextCells = Uint8List.fromList(_cells);
    for (var i = 0; i < removeCount; i++) {
      final move = _history[_history.length - 1 - i];
      nextCells[move.coordinate.index] = Stone.empty.code;
    }
    return BoardState._(
      nextCells,
      _history.sublist(0, _history.length - removeCount),
    );
  }
}
