import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'leaderboard_entry.dart';
import '../../services/firebase_service.dart';
import '../../../models/badge.dart' as badge_model;
import '../../services/badge_service.dart';

class MyBadgeView extends StatefulWidget {
  final LeaderboardEntry? entry;
  final String parentId;
  final String childId;

  const MyBadgeView({
    Key? key,
    this.entry,
    required this.parentId,
    required this.childId,
  }) : super(key: key);

  @override
  State<MyBadgeView> createState() => _MyBadgeViewState();
}

class _MyBadgeViewState extends State<MyBadgeView> {
  LeaderboardEntry? _entry;
  bool _isLoading = true;
  List<RecentPurchase> _allPurchases = [];
  List<badge_model.Badge> _badges = [];

  @override
  void initState() {
    super.initState();
    _loadMyBadgeData();
    _loadBadges();
    // Check all badges when screen loads
    BadgeService.checkAllBadges(widget.parentId, widget.childId);
  }

  Future<void> _loadBadges() async {
    try {
      final badges = await BadgeService.getChildBadges(
        widget.parentId,
        widget.childId,
      );
      // Debug: Print badge image paths
      for (final badge in badges) {
        print(
          '📛 Badge: ${badge.name} - Image: ${badge.imageAsset} - Unlocked: ${badge.isUnlocked}',
        );
      }
      setState(() {
        _badges = badges;
      });
    } catch (e) {
      print('Error loading badges: $e');
    }
  }

  Future<void> _loadMyBadgeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get wallet
      final wallet = await FirebaseService.getChildWallet(
        widget.parentId,
        widget.childId,
      );

      final totalSaved = wallet?.savingBalance ?? 0.0;
      final totalSpent = wallet?.spendingBalance ?? 0.0;

      // Calculate points and level
      final points = LeaderboardEntry.calculatePoints(totalSaved);
      final currentLevel = LeaderboardEntry.calculateLevel(totalSaved);
      final progress = LeaderboardEntry.calculateProgressToNextLevel(
        totalSaved,
      );

      // Get all purchases
      try {
        final transactions = await FirebaseService.getChildTransactions(
          widget.parentId,
          widget.childId,
        );
        final spendingTransactions =
            transactions
                .where(
                  (t) =>
                      t.type.toLowerCase() == 'spending' &&
                      t.fromWallet.toLowerCase() == 'spending',
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));

        _allPurchases = spendingTransactions
            .map(
              (t) => RecentPurchase(
                description: t.description,
                amount: t.amount,
                date: t.date,
              ),
            )
            .toList();
      } catch (e) {
        print('Error loading transactions: $e');
      }

      // Get child name from entry or create default
      final name = widget.entry?.name ?? 'You';
      final avatarUrl = widget.entry?.avatarUrl ?? '';

      setState(() {
        _entry = LeaderboardEntry(
          id: widget.childId,
          name: name,
          avatarUrl: avatarUrl,
          totalSaved: totalSaved,
          totalSpent: totalSpent,
          points: points,
          currentLevel: currentLevel,
          progressToNextLevel: progress,
          recentPurchases: _allPurchases,
          rank: 0,
        );
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading badge data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF643FDB)),
        ),
      );
    }

    if (_entry == null) {
      return Center(
        child: Text(
          'No data available',
          style: TextStyle(
            fontSize: 16.sp,
            color: Colors.grey[600],
            fontFamily: 'SPProText',
          ),
        ),
      );
    }

    final nextLevelThreshold = LeaderboardEntry.getNextLevelThreshold(
      _entry!.totalSaved,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large Badge Icon
          Container(
            width: 120.w,
            height: 120.w,
            decoration: BoxDecoration(
              color: _getBadgeColor(_entry!.currentLevel).withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: _getBadgeColor(_entry!.currentLevel),
                width: 4.w,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.emoji_events,
                size: 60.sp,
                color: _getBadgeColor(_entry!.currentLevel),
              ),
            ),
          ),
          SizedBox(height: 20.h),

          // Level Text
          Text(
            'Level ${_entry!.currentLevel}',
            style: TextStyle(
              fontSize: 32.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1C1243),
              fontFamily: 'SPProText',
            ),
          ),
          SizedBox(height: 4.h),
          // Clarification that level depends on saving money
          Text(
            'Based on money saved',
            style: TextStyle(
              fontSize: 14.sp,
              color: const Color(0xFF6B7280),
              fontFamily: 'SPProText',
            ),
          ),
          SizedBox(height: 8.h),

          // Points
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stars, size: 24.sp, color: const Color(0xFFFFD700)),
              SizedBox(width: 8.w),
              Text(
                '${_entry!.points} ${_entry!.points == 1 ? 'point' : 'points'}',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                  fontFamily: 'SPProText',
                ),
              ),
            ],
          ),
          SizedBox(height: 32.h),

          // Progress to Next Level
          if (nextLevelThreshold != null) ...[
            Text(
              'Progress to Level ${_entry!.currentLevel + 1}',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1C1243),
                fontFamily: 'SPProText',
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '${_entry!.totalSaved.toStringAsFixed(0)} / ${nextLevelThreshold.toStringAsFixed(0)} SAR',
              style: TextStyle(
                fontSize: 14.sp,
                color: const Color(0xFF6B7280),
                fontFamily: 'SPProText',
              ),
            ),
            SizedBox(height: 12.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: LinearProgressIndicator(
                value: _entry!.progressToNextLevel,
                minHeight: 24.h,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF643FDB),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: const Color(0xFF47C272).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: const Color(0xFF47C272), width: 2.w),
              ),
              child: Text(
                'Max Level Achieved! 🏆',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF47C272),
                  fontFamily: 'SPProText',
                ),
              ),
            ),
          ],
          SizedBox(height: 32.h),

          // Achievement Badges Section
          Text(
            'Achievement Badges',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1C1243),
              fontFamily: 'SPProText',
            ),
          ),
          SizedBox(height: 16.h),

          // Badge Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12.w,
              mainAxisSpacing: 12.h,
              childAspectRatio:
                  0.75, // Increased vertical space for progress bar
            ),
            itemCount: _badges.length,
            itemBuilder: (context, index) {
              final badge = _badges[index];
              return _buildBadgeCard(badge);
            },
          ),
          SizedBox(height: 32.h),

          // Points Information Section
          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.stars,
                      size: 24.sp,
                      color: const Color(0xFFFFD700),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'How Points Work',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1C1243),
                        fontFamily: 'SPProText',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Text(
                  'You earn points by saving money!',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1243),
                    fontFamily: 'SPProText',
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '• Every 100 SAR saved = 10 points\n• Your level increases based on how much money you save\n• Keep saving to level up and unlock new badges!',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: const Color(0xFF6B7280),
                    fontFamily: 'SPProText',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(badge_model.Badge badge) {
    return FutureBuilder<Map<String, dynamic>>(
      future: BadgeService.getBadgeProgress(
        widget.parentId,
        widget.childId,
        badge.type,
      ),
      builder: (context, snapshot) {
        final progressData =
            snapshot.data ?? {'current': 0, 'target': 1, 'progress': 0.0};
        final current = progressData['current'] as num;
        final target = progressData['target'] as num;
        final progress = (progressData['progress'] as num).toDouble();
        final isRankBased = progressData['isRankBased'] as bool? ?? false;
        final rank = progressData['rank'] as int? ?? 0;
        final totalPlayers = progressData['totalPlayers'] as int? ?? 0;

        return GestureDetector(
          onTap: () {
            _showBadgeExplanation(badge);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: badge.isUnlocked
                    ? const Color(0xFFFFD700)
                    : Colors.grey[300]!,
                width: badge.isUnlocked ? 2.w : 1.w,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8.r,
                  offset: Offset(0, 2.h),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Badge Image
                Container(
                  width: 70.w,
                  height: 70.w,
                  decoration: BoxDecoration(
                    color: badge.isUnlocked
                        ? Colors.transparent
                        : Colors.grey[200]!.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: badge.imageAsset.isEmpty
                      ? _buildDefaultBadgeIcon(badge.isUnlocked)
                      : badge.isUnlocked
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: Image.asset(
                            badge.imageAsset,
                            width: 70.w,
                            height: 70.w,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              print(
                                '❌ Error loading badge image: ${badge.imageAsset}',
                              );
                              print('❌ Error details: $error');
                              print('❌ Stack trace: $stackTrace');
                              return _buildDefaultBadgeIcon(true);
                            },
                          ),
                        )
                      : Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12.r),
                              child: Image.asset(
                                badge.imageAsset,
                                width: 70.w,
                                height: 70.w,
                                fit: BoxFit.contain,
                                color: Colors.grey[400],
                                colorBlendMode: BlendMode.saturation,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildDefaultBadgeIcon(false);
                                },
                              ),
                            ),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Icon(
                                  Icons.lock,
                                  size: 24.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                SizedBox(height: 6.h),

                // Badge Name
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: Text(
                    badge.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: badge.isUnlocked
                          ? const Color(0xFF1C1243)
                          : Colors.grey[500],
                      fontFamily: 'SPProText',
                    ),
                  ),
                ),
                SizedBox(height: 6.h),

                // Progress Bar (only show if not unlocked)
                if (!badge.isUnlocked) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Column(
                      children: [
                        // Progress text
                        Text(
                          isRankBased
                              ? 'Rank: $rank/$totalPlayers'
                              : '${current.toInt()}/${target.toInt()}',
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: Colors.grey[600],
                            fontFamily: 'SPProText',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4.r),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4.h,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF643FDB),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Show "Unlocked" text if badge is unlocked
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    child: Text(
                      'Unlocked!',
                      style: TextStyle(
                        fontSize: 9.sp,
                        color: const Color(0xFF47C272),
                        fontFamily: 'SPProText',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBadgeExplanation(badge_model.Badge badge) {
    final explanation = _getBadgeExplanation(badge.type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          explanation,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            fontFamily: 'SPProText',
          ),
        ),
        backgroundColor: const Color(0xFF643FDB),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        margin: EdgeInsets.all(16.w),
      ),
    );
  }

  String _getBadgeExplanation(badge_model.BadgeType badgeType) {
    switch (badgeType) {
      case badge_model.BadgeType.tenaciousTaskmaster:
        return 'Complete 10 tasks to unlock this badge! Keep completing tasks and you\'ll earn it.';
      case badge_model.BadgeType.financialFreedomFlyer:
        return 'Save 100 SAR to unlock this badge! Keep saving money in your savings wallet.';
      case badge_model.BadgeType.conquerorsCrown:
        return 'Win first place in a weekly challenge to unlock this badge! Complete challenge tasks faster than your siblings.';
      case badge_model.BadgeType.highPriorityHero:
        return 'Complete 4 high-priority tasks to unlock this badge! Focus on tasks marked as high priority.';
      case badge_model.BadgeType.wishlistFulfillment:
        return 'Purchase 5 items from your wishlist to unlock this badge! Save up and buy items you want.';
    }
  }

  Color _getBadgeColor(int level) {
    final colors = [
      const Color(0xFFE5E7EB),
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
      const Color(0xFF643FDB),
    ];
    return level < colors.length ? colors[level] : colors[colors.length - 1];
  }

  Widget _buildDefaultBadgeIcon(bool isUnlocked) {
    return Container(
      decoration: BoxDecoration(
        color: isUnlocked
            ? const Color(0xFFFFD700).withOpacity(0.2)
            : Colors.grey[200],
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.emoji_events,
        size: 40.sp,
        color: isUnlocked ? const Color(0xFFFFD700) : Colors.grey[400],
      ),
    );
  }
}
