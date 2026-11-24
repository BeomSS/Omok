/// Win/loss/draw record for a single AI difficulty tier.
class DifficultyStats {
  const DifficultyStats({
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  factory DifficultyStats.fromJson(Map<String, dynamic> json) =>
      DifficultyStats(
        wins: json['wins'] as int? ?? 0,
        losses: json['losses'] as int? ?? 0,
        draws: json['draws'] as int? ?? 0,
      );

  final int wins;
  final int losses;
  final int draws;

  int get totalGames => wins + losses + draws;

  int get winRatePercent =>
      totalGames == 0 ? 0 : ((wins / totalGames) * 100).round();

  DifficultyStats recordWin() =>
      DifficultyStats(wins: wins + 1, losses: losses, draws: draws);

  DifficultyStats recordLoss() =>
      DifficultyStats(wins: wins, losses: losses + 1, draws: draws);

  DifficultyStats recordDraw() =>
      DifficultyStats(wins: wins, losses: losses, draws: draws + 1);

  Map<String, dynamic> toJson() => {
        'wins': wins,
        'losses': losses,
        'draws': draws,
      };
}
