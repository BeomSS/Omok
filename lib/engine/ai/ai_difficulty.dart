/// AI difficulty tiers for offline single-player matches.
enum AiDifficulty {
  beginner(
    label: '초급',
    description: '입문자를 위한 편안한 난이도',
    maxThinkMs: 300,
    minDisplayDelayMs: 300,
  ),
  intermediate(
    label: '중급',
    description: '기본 공방과 3·4 위협을 대응하는 난이도',
    maxThinkMs: 500,
    minDisplayDelayMs: 300,
  ),
  advanced(
    label: '고급',
    description: '띈 패턴과 4-3 전술까지 읽는 본격 난이도',
    maxThinkMs: 1200,
    minDisplayDelayMs: 350,
  ),
  expert(
    label: '전문가',
    description: '연속 4목(VCF)과 깊은 수읽기를 구사하는 최고 난이도',
    maxThinkMs: 2500,
    minDisplayDelayMs: 400,
  );

  const AiDifficulty({
    required this.label,
    required this.description,
    required this.maxThinkMs,
    required this.minDisplayDelayMs,
  });

  final String label;
  final String description;

  /// Hard time budget for search inside the background Isolate.
  final int maxThinkMs;

  /// Minimum artificial delay so fast moves remain readable on screen.
  final int minDisplayDelayMs;
}
