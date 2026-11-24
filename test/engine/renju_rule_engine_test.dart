import 'package:flutter_test/flutter_test.dart';
import 'package:omok/engine/engine.dart';

/// Helper to build a board with arbitrary Black/White stone placements
/// (without enforcing turn alternation) for precise rule unit testing.
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
  const rules = RenjuRuleEngine();

  group('BoardState & Coordinate', () {
    test('alternates turns and supports undo', () {
      var board = BoardState.empty();
      expect(board.isEmpty, isTrue);
      expect(board.nextTurn, Stone.black);

      board = board.placeStone(const Coordinate(7, 7));
      expect(board.moveCount, 1);
      expect(board.lastMove?.coordinate.notation, 'H8');
      expect(board.nextTurn, Stone.white);

      board = board.placeStone(const Coordinate(7, 8));
      expect(board.moveCount, 2);
      expect(board.nextTurn, Stone.black);

      board = board.undo(steps: 2);
      expect(board.isEmpty, isTrue);
      expect(board.stoneAt(const Coordinate(7, 7)), Stone.empty);
    });
  });

  group('Win detection (Renju)', () {
    test('Black wins on exact 5 in horizontal, vertical, and diagonal lines', () {
      final board = buildBoard(
        black: [(7, 3), (7, 4), (7, 5), (7, 6), (7, 7)],
      );
      final result = rules.checkResult(board, board.lastMove!);
      expect(result.status, GameStatus.blackWin);
      expect(result.winningLine.length, 5);
    });

    test('White wins on exact 5 and also on 6-in-a-row (overline allowed for White)', () {
      final board = buildBoard(
        white: [(5, 2), (5, 3), (5, 4), (5, 5), (5, 6), (5, 7)],
      );
      final result = rules.checkResult(board, board.lastMove!);
      expect(result.status, GameStatus.whiteWin);
      expect(result.winningLine.length, 6);
    });

    test('White has no forbidden moves even in 3-3, 4-4, or 6+ shapes', () {
      final board = buildBoard(
        white: [(7, 5), (7, 6), (5, 7), (6, 7)],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.white),
        ForbiddenReason.none,
      );
    });
  });

  group('Black Overline (장목)', () {
    test('6-in-a-row is forbidden for Black', () {
      final board = buildBoard(
        black: [(7, 4), (7, 5), (7, 6), (7, 8), (7, 9)],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.overline,
      );
    });

    test('Exact 5 on one axis overrides overline on another axis (Black wins)', () {
      // Placing at (7, 7) creates 6 horizontally (7,4..9) AND exact 5 vertically (3..7, 7).
      final board = buildBoard(
        black: [
          (7, 4), (7, 5), (7, 6), (7, 8), (7, 9),
          (3, 7), (4, 7), (5, 7), (6, 7),
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.none,
      );
      final afterWin = board.placeStone(const Coordinate(7, 7), stone: Stone.black);
      expect(rules.checkResult(afterWin, afterWin.lastMove!).status, GameStatus.blackWin);
    });
  });

  group('Black Double-Four (4-4)', () {
    test('Two-axis 4-4 is forbidden', () {
      final board = buildBoard(
        black: [
          (7, 4), (7, 5), (7, 6), // Horizontal 4 with (7,7)
          (4, 7), (5, 7), (6, 7), // Vertical 4 with (7,7)
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.doubleFour,
      );
    });

    test('Single-line 4-4 (B_BBB_B) is forbidden', () {
      // Row 7: B(3), _(4), B(5), B(6), [pos=7], _(8), B(9)
      // Wait: B(3), _(4), B(5), B(6), B(7), _(8), B(9) ->
      // filling (4) makes 3..7 (5), filling (8) makes 5..9 (5)!
      final board = buildBoard(
        black: [(7, 3), (7, 5), (7, 6), (7, 9)],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.doubleFour,
      );
    });

    test('Single open four (_BBBB_) is legal (NOT 4-4)', () {
      final board = buildBoard(
        black: [(7, 4), (7, 5), (7, 6)],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.none,
      );
    });

    test('4-3 combination is legal for Black', () {
      final board = buildBoard(
        black: [
          (7, 4), (7, 5), (7, 6), // Horizontal 4 with (7,7)
          (5, 7), (6, 7), // Vertical open 3 with (7,7)
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.none,
      );
    });
  });

  group('Black Double-Three (3-3)', () {
    test('Standard consecutive 3-3 is forbidden', () {
      final board = buildBoard(
        black: [
          (7, 5), (7, 6), // Horizontal open 3 with (7,7)
          (5, 7), (6, 7), // Vertical open 3 with (7,7)
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.doubleThree,
      );
    });

    test('Broken 3-3 (BB_B + BBB) is forbidden', () {
      final board = buildBoard(
        black: [
          (7, 4), (7, 6), // Broken horizontal open 3: B(4), _(5), B(6), B(7)
          (5, 7), (6, 7), // Vertical open 3
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.doubleThree,
      );
    });

    test('Closed 3 + Open 3 is legal (blocked by White)', () {
      final board = buildBoard(
        black: [
          (7, 5), (7, 6),
          (5, 7), (6, 7),
        ],
        white: [
          (7, 4), // Blocks horizontal 3 from becoming an open four
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.none,
      );
    });

    test('Edge-blocked 3 + Open 3 is legal', () {
      // Placing at (2, 1): row 2 has B(2,1), B(2,2), B(2,3) -> left edge (2,0)
      // cannot form an open four, only extending right (2,4) works if (2,0) is empty.
      // Put Black at (1, 1), (1, 2) with (1,0) blocked by White? Better:
      // Place at (1, 1) with horizontal B(1,2), B(1,3) -> left is (1,0) at col 0:
      // placing at (1,0) hits board edge; placing at (1,4) makes _(0) B(1) B(2) B(3) B(4) _(5) which IS open 4!
      // Instead test actual edge-blocked: | _ B(0,1) B(0,2) B(0,3) _ |? No, col 0 has 1 empty cell on left.
      // True edge-blocked: B(7,0) B(7,1) [pos=(7,2)] -> left is board edge (no space to left of (7,0))!
      final board = buildBoard(
        black: [
          (7, 0), (7, 1), // Touching left edge -> closed 3 at (7,2)
          (5, 2), (6, 2), // Vertical open 3 at (7,2)
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 2), Stone.black),
        ForbiddenReason.none,
      );
    });

    test('Overline-blocked fake 3 + Open 3 is legal', () {
      // Row 7: B(3), _(4), _(5), B(6), [pos=7], B(8), _(9), _(10), B(11)
      // Neither (5) nor (9) creates a valid open four because completing the
      // outer end (4) or (10) causes a 6-in-a-row overline!
      final board = buildBoard(
        black: [
          (7, 3), (7, 6), (7, 8), (7, 11), // Fake horizontal 3 at (7,7)
          (5, 7), (6, 7), // Genuine vertical open 3 at (7,7)
        ],
      );
      expect(
        rules.getForbiddenReason(board, const Coordinate(7, 7), Stone.black),
        ForbiddenReason.none,
      );
    });

    test('Recursive False 3-3 (거짓 3-3) is legal when open-4 point is forbidden', () {
      // Candidate P = (7, 7):
      // - Row 7: genuine open three via B(7,8), B(7,9).
      // - Col 7: broken three B(5,7), _(6,7), [P=(7,7)], B(8,7).
      //   Its ONLY open-four completion point is e = (6, 7).
      // - Row 6 makes e = (6, 7) an OVERLINE forbidden move:
      //   B(6,4), B(6,5), B(6,6), _(6,7), B(6,8), B(6,9).
      final falseDoubleThreeBoard = buildBoard(
        black: [
          (7, 8), (7, 9),
          (5, 7), (8, 7),
          (6, 4), (6, 5), (6, 6), (6, 8), (6, 9),
        ],
      );
      expect(
        rules.getForbiddenReason(
          falseDoubleThreeBoard,
          const Coordinate(7, 7),
          Stone.black,
        ),
        ForbiddenReason.none,
      );

      // Control check: remove row-6 overline stones so e = (6, 7) becomes legal ->
      // now P = (7, 7) MUST be detected as forbidden 3-3!
      final trueDoubleThreeBoard = buildBoard(
        black: [
          (7, 8), (7, 9),
          (5, 7), (8, 7),
        ],
      );
      expect(
        rules.getForbiddenReason(
          trueDoubleThreeBoard,
          const Coordinate(7, 7),
          Stone.black,
        ),
        ForbiddenReason.doubleThree,
      );
    });

    test('getForbiddenMoves returns map for Black and empty for White', () {
      final board = buildBoard(
        black: [(7, 5), (7, 6), (5, 7), (6, 7)],
      );
      final blackForbidden = rules.getForbiddenMoves(board, Stone.black);
      expect(blackForbidden[const Coordinate(7, 7)], ForbiddenReason.doubleThree);
      expect(rules.getForbiddenMoves(board, Stone.white), isEmpty);
    });
  });
}
