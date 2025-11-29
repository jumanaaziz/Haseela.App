class LeaderboardEntry {
  final String id;
  final String name;
  final String avatarUrl;
  final double totalSaved; // Total money saved (SAR)
  final double totalSpent; // Total money spent (SAR)
  final int points; // Points earned (every 100 SAR saved = 10 points)
  final int currentLevel; // Current badge level
  final double progressToNextLevel; // Progress to next badge (0.0 to 1.0)
  final List<RecentPurchase> recentPurchases; // Recent purchases
  final int rank;
  final int challengeCompletions; // Number of challenge tasks completed
  final DateTime?
  earliestChallengeCompletion; // Earliest challenge completion date
  // test
  LeaderboardEntry({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.totalSaved,
    required this.totalSpent,
    required this.points,
    required this.currentLevel,
    required this.progressToNextLevel,
    required this.recentPurchases,
    required this.rank,
    this.challengeCompletions = 0,
    this.earliestChallengeCompletion,
  });

  // Badge thresholds
  static const List<double> badgeThresholds = [100.0, 300.0, 500.0, 1000.0];

  // Calculate points: every 100 SAR saved = 10 points
  static int calculatePoints(double totalSaved) {
    return ((totalSaved / 100.0) * 10).floor();
  }

  // Calculate current level based on total saved
  static int calculateLevel(double totalSaved) {
    for (int i = badgeThresholds.length - 1; i >= 0; i--) {
      if (totalSaved >= badgeThresholds[i]) {
        return i + 1;
      }
    }
    return 0;
  }

  // Calculate progress to next level (0.0 to 1.0)
  static double calculateProgressToNextLevel(double totalSaved) {
    final currentLevel = calculateLevel(totalSaved);

    if (currentLevel >= badgeThresholds.length) {
      return 1.0; // Max level reached
    }

    final currentThreshold = currentLevel > 0
        ? badgeThresholds[currentLevel - 1]
        : 0.0;
    final nextThreshold = badgeThresholds[currentLevel];
    final progress =
        (totalSaved - currentThreshold) / (nextThreshold - currentThreshold);

    return progress.clamp(0.0, 1.0);
  }

  // Get next level threshold
  static double? getNextLevelThreshold(double totalSaved) {
    final currentLevel = calculateLevel(totalSaved);
    if (currentLevel >= badgeThresholds.length) {
      return null; // Max level
    }
    return badgeThresholds[currentLevel];
  }
}

class RecentPurchase {
  final String description;
  final double amount;
  final DateTime date;

  RecentPurchase({
    required this.description,
    required this.amount,
    required this.date,
  });

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
