import 'package:flutter_test/flutter_test.dart';
import 'package:omok/engine/engine.dart';

BoardState buildBoard({
  List<(int, int)> black = const [],
  List<(int, int)> white = const [],
}) {
  var board = BoardState.empty();
  for (final (r, c) in black) {
    board = board.placeStone(Coordinate(r, c), stone: Stone.black);
  }
  for (final (r, c) in white) {
    board = board.placeStone(Coordinate(r, c), stone: Stone.white);
  }
  return board;
}

void main() {
  const freestyle = FreestyleRuleEngine();

  group('FreestyleRuleEngine', () {
    test('allows Black 3-3, 4-4, and 6-in-a-row without forbidden moves', () {
      final threeThreeBoard = buildBoard(
        black: [(7, 5), (7, 6), (5, 7), (6, 7)],
      );
      expect(
        freestyle.getForbiddenReason(
          threeThreeBoard,
          const Coordinate(7, 7),
          Stone.black,
        ),
        ForbiddenReason.none,
      );
      expect(freestyle.getForbiddenMoves(threeThreeBoard, Stone.black), isEmpty);
    });

    test('Black wins on 6-in-a-row under Freestyle rules', () {
      final board = buildBoard(
        black: [(7, 4), (7, 5), (7, 6), (7, 7), (7, 8), (7, 9)],
      );
      final result = freestyle.checkResult(board, board.lastMove!);
      expect(result.status, GameStatus.blackWin);
      expect(result.winningLine.length, 6);
    });

    test('AI recognizes Black 6-in-a-row immediate win under Freestyle', () {
      final board = buildBoard(
        black: [(7, 4), (7, 5), (7, 6), (7, 8), (7, 9)],
        white: [(6, 4), (6, 5), (6, 6)],
      );
      final ai = DartAiEngine();
      final move = ai.findBestMoveSync(
        board: board,
        aiStone: Stone.black,
        difficulty: AiDifficulty.intermediate,
        ruleEngine: freestyle,
      );
      expect(move, const Coordinate(7, 7));
    });
  });
}
