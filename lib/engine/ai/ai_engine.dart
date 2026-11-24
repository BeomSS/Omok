import '../model/board_state.dart';
import '../model/coordinate.dart';
import '../model/stone.dart';
import '../rules/rule_engine.dart';
import 'ai_difficulty.dart';

/// Contract for pluggable Omok AI engines.
///
/// MVP uses a pure Dart implementation executed inside a background Isolate.
/// Future upgrades (e.g., C++/Rust FFI or NNUE engines) can swap in behind
/// this same interface without modifying UI or controller code.
abstract class AiEngine {
  Future<Coordinate> findBestMove({
    required BoardState board,
    required Stone aiStone,
    required AiDifficulty difficulty,
    required RuleEngine ruleEngine,
  });
}
