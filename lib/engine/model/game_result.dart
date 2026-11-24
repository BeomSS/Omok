import 'coordinate.dart';
import 'stone.dart';

/// Current status of an Omok game.
enum GameStatus {
  ongoing,
  blackWin,
  whiteWin,
  draw;

  bool get isFinished => this != GameStatus.ongoing;

  Stone? get winner => switch (this) {
        GameStatus.blackWin => Stone.black,
        GameStatus.whiteWin => Stone.white,
        _ => null,
      };
}

/// Outcome of evaluating the board after a move (or a turn timeout).
class GameResult {
  const GameResult({
    required this.status,
    this.winningLine = const [],
    this.isTimeout = false,
  });

  static const GameResult ongoing = GameResult(status: GameStatus.ongoing);
  static const GameResult draw = GameResult(status: GameStatus.draw);

  factory GameResult.timeout({required Stone winner}) => GameResult(
        status: winner == Stone.black
            ? GameStatus.blackWin
            : GameStatus.whiteWin,
        isTimeout: true,
      );

  final GameStatus status;

  /// Coordinates forming the winning 5+ line (empty if ongoing, draw, or timeout).
  final List<Coordinate> winningLine;

  /// True if the game ended because the opposing player ran out of turn time.
  final bool isTimeout;
}
