import '../model/board_state.dart';
import '../model/coordinate.dart';

/// Abstraction for any turn provider: offline AI, local human, or future
/// online multiplayer opponent.
abstract class MoveSource {
  /// Resolves the next move coordinate for the given [board].
  /// Returns `null` if cancelled before a move is chosen.
  Future<Coordinate?> nextMove(BoardState board);

  /// Cancels any pending computation or network wait (e.g., on undo or exit)
  /// to prevent stale moves from racing onto the board.
  void cancel();
}
