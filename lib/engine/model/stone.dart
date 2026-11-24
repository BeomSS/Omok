/// Represents a stone or empty intersection on the 15x15 Omok board.
enum Stone {
  empty(0),
  black(1),
  white(2);

  const Stone(this.code);

  /// Compact numeric representation for flat [Uint8List] board buffers.
  final int code;

  /// Returns the opposing stone, or [Stone.empty] if called on [Stone.empty].
  Stone get opponent => switch (this) {
        Stone.black => Stone.white,
        Stone.white => Stone.black,
        Stone.empty => Stone.empty,
      };

  static Stone fromCode(int code) => switch (code) {
        1 => Stone.black,
        2 => Stone.white,
        _ => Stone.empty,
      };
}
