import 'dart:typed_data';

import '../model/coordinate.dart';
import '../model/stone.dart';

/// Transposition table bound type for Alpha-Beta search.
enum TtFlag {
  exact,
  lowerBound,
  upperBound,
}

/// Cached evaluation entry in [ZobristTranspositionTable].
class TtEntry {
  const TtEntry({
    required this.hash,
    required this.depth,
    required this.score,
    required this.flag,
    required this.bestMoveIdx,
  });

  final int hash;
  final int depth;
  final int score;
  final TtFlag flag;
  final int bestMoveIdx;
}

/// Deterministic 64-bit Zobrist hashing and fixed-size transposition table.
class ZobristTable {
  ZobristTable({int tableSizePower = 16})
      : _mask = (1 << tableSizePower) - 1,
        _entries = List<TtEntry?>.filled(1 << tableSizePower, null) {
    // Deterministic SplitMix64 generator for reproducible hash keys.
    var seed = 0x517CC1B727220A95;
    int nextKey() {
      seed = (seed + 0x9E3779B97F4A7C15);
      var z = seed;
      z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
      z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
      return z ^ (z >>> 31);
    }

    _blackKeys = Int64List(kBoardCellCount);
    _whiteKeys = Int64List(kBoardCellCount);
    for (var i = 0; i < kBoardCellCount; i++) {
      _blackKeys[i] = nextKey();
      _whiteKeys[i] = nextKey();
    }
    sideToMoveKey = nextKey();
  }

  late final Int64List _blackKeys;
  late final Int64List _whiteKeys;
  late final int sideToMoveKey;

  final int _mask;
  final List<TtEntry?> _entries;

  /// Computes full Zobrist hash from scratch for [cells] and [turnCode].
  int computeHash(Uint8List cells, int turnCode) {
    var h = 0;
    for (var i = 0; i < kBoardCellCount; i++) {
      final c = cells[i];
      if (c == Stone.black.code) {
        h ^= _blackKeys[i];
      } else if (c == Stone.white.code) {
        h ^= _whiteKeys[i];
      }
    }
    if (turnCode == Stone.white.code) {
      h ^= sideToMoveKey;
    }
    return h;
  }

  /// Incrementally toggles a stone at [index] for [stoneCode].
  int toggleStone(int hash, int index, int stoneCode) {
    if (stoneCode == Stone.black.code) {
      return hash ^ _blackKeys[index];
    }
    if (stoneCode == Stone.white.code) {
      return hash ^ _whiteKeys[index];
    }
    return hash;
  }

  int toggleTurn(int hash) => hash ^ sideToMoveKey;

  TtEntry? probe(int hash) {
    final entry = _entries[hash & _mask];
    if (entry != null && entry.hash == hash) {
      return entry;
    }
    return null;
  }

  void store({
    required int hash,
    required int depth,
    required int score,
    required TtFlag flag,
    required int bestMoveIdx,
  }) {
    final slot = hash & _mask;
    final existing = _entries[slot];
    // Replace if empty, different position, or deeper/equal search.
    if (existing == null || existing.hash != hash || depth >= existing.depth) {
      _entries[slot] = TtEntry(
        hash: hash,
        depth: depth,
        score: score,
        flag: flag,
        bestMoveIdx: bestMoveIdx,
      );
    }
  }

  void clear() {
    _entries.fillRange(0, _entries.length, null);
  }
}
