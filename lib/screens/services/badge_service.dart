import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/badge.dart';
import 'firebase_service.dart';

class BadgeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all badges for a child
  static Future<List<Badge>> getChildBadges(
    String parentId,
    String childId,
  ) async {
    try {
      final badgesRef = _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Badges');

      final snapshot = await badgesRef.get();

      if (snapshot.docs.isEmpty) {
        // Initialize default badges
        final initialized = await _initializeBadges(parentId, childId);
        // Ensure latest metadata (names/images) after init
        await _verifyAndMigrateBadges(parentId, childId);
        return initialized;
      }

      // Always verify and migrate to ensure image paths are up to date
      await _verifyAndMigrateBadges(parentId, childId);

      // Get refreshed badges after migration
      final refreshed = await badgesRef.get();
      final badges = refreshed.docs
          .map((doc) => Badge.fromFirestore(doc))
          .toList();

      // Debug: Print all badge image paths
      print('📛 Loaded ${badges.length} badges:');
      for (final badge in badges) {
        print(
          '   - ${badge.name}: ${badge.imageAsset} (unlocked: ${badge.isUnlocked})',
        );
      }

      return badges;
    } catch (e) {
      print('Error getting badges: $e');
      return Badge.getDefaultBadges();
    }
  }

  /// Ensure Firestore badge docs match latest definitions
  static Future<void> _verifyAndMigrateBadges(
    String parentId,
    String childId,
  ) async {
    try {
      final defaults = Badge.getDefaultBadges();
      final badgesRef = _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Badges');

      final existingSnap = await badgesRef.get();
      final existingIds = existingSnap.docs.map((d) => d.id).toSet();

      // Create any missing badges
      for (final def in defaults) {
        if (!existingIds.contains(def.id)) {
          print(
            '➕ Creating new badge: ${def.id} with image: ${def.imageAsset}',
          );
          await badgesRef.doc(def.id).set(def.toFirestore());
        }
      }

      // Update metadata (name/description/imageAsset) if changed
      for (final def in defaults) {
        final doc = await badgesRef.doc(def.id).get();
        if (!doc.exists) continue;
        final data = doc.data() as Map<String, dynamic>;
        final updates = <String, dynamic>{};
        if ((data['name'] ?? '') != def.name) updates['name'] = def.name;
        if ((data['description'] ?? '') != def.description) {
          updates['description'] = def.description;
        }
        final currentImageAsset = (data['imageAsset'] ?? '').toString();
        if (currentImageAsset != def.imageAsset) {
          print(
            '🔄 Updating badge ${def.id} imageAsset: "$currentImageAsset" → "${def.imageAsset}"',
          );
          updates['imageAsset'] = def.imageAsset;
        }
        // Ensure type field is consistent
        final expectedType = def.type.toString().split('.').last;
        if ((data['type'] ?? '') != expectedType)
          updates['type'] = expectedType;

        if (updates.isNotEmpty) {
          print('✅ Updating badge ${def.id} with: $updates');
          await badgesRef.doc(def.id).update(updates);
        }
      }
    } catch (e) {
      print('Error verifying/migrating badges: $e');
    }
  }

  /// Initialize default badges for a child
  static Future<List<Badge>> _initializeBadges(
    String parentId,
    String childId,
  ) async {
    final defaultBadges = Badge.getDefaultBadges();
    final badgesRef = _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Badges');

    for (final badge in defaultBadges) {
      await badgesRef.doc(badge.id).set(badge.toFirestore());
    }

    return defaultBadges;
  }

  /// Convert BadgeType to badge document ID
  static String _getBadgeId(BadgeType badgeType) {
    switch (badgeType) {
      case BadgeType.tenaciousTaskmaster:
        return 'tenacious_taskmaster';
      case BadgeType.financialFreedomFlyer:
        return 'financial_freedom_flyer';
      case BadgeType.conquerorsCrown:
        return 'conquerors_crown';
      case BadgeType.highPriorityHero:
        return 'high_priority_hero';
      case BadgeType.wishlistFulfillment:
        return 'wishlist_fulfillment';
    }
  }

  /// Unlock a badge for a child
  static Future<void> unlockBadge(
    String parentId,
    String childId,
    BadgeType badgeType,
  ) async {
    try {
      final badgeId = _getBadgeId(badgeType);
      final badgeRef = _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Badges')
          .doc(badgeId);

      final badgeDoc = await badgeRef.get();

      if (!badgeDoc.exists) {
        // Initialize badges if they don't exist
        await _initializeBadges(parentId, childId);
      }

      // Check if already unlocked
      final currentData = badgeDoc.data();
      if (currentData != null && currentData['isUnlocked'] == true) {
        return; // Already unlocked
      }

      // Unlock the badge
      await badgeRef.update({
        'isUnlocked': true,
        'unlockedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Badge unlocked: $badgeType');
    } catch (e) {
      print('Error unlocking badge: $e');
    }
  }

  /// Check and unlock Tenacious Taskmaster badge (10 tasks completed)
  /// Condition: Complete 10 tasks (status = 'done')
  static Future<void> checkTenaciousTaskmaster(
    String parentId,
    String childId,
  ) async {
    try {
      // Get all tasks with status 'done' (approved by parent)
      final tasksSnapshot = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Tasks')
          .where('status', isEqualTo: 'done')
          .get();

      final completedTasksCount = tasksSnapshot.docs.length;
      print(
        '📊 Checking "Do 10 Tasks" badge: $completedTasksCount tasks completed',
      );

      if (completedTasksCount >= 10) {
        print('✅ Unlocking "Do 10 Tasks" badge - condition met!');
        await unlockBadge(parentId, childId, BadgeType.tenaciousTaskmaster);
      } else {
        print(
          '⏳ "Do 10 Tasks" badge: Need ${10 - completedTasksCount} more tasks',
        );
      }
    } catch (e) {
      print('❌ Error checking Tenacious Taskmaster: $e');
    }
  }

  /// Check and unlock Financial Freedom Flyer badge (100 SAR saved)
  /// Condition: Save 100 SAR (savingBalance >= 100.0)
  static Future<void> checkFinancialFreedomFlyer(
    String parentId,
    String childId,
  ) async {
    try {
      final wallet = await FirebaseService.getChildWallet(parentId, childId);

      if (wallet != null) {
        final savingBalance = wallet.savingBalance;
        print('📊 Checking "Save 100 SAR" badge: $savingBalance SAR saved');

        if (savingBalance >= 100.0) {
          print('✅ Unlocking "Save 100 SAR" badge - condition met!');
          await unlockBadge(parentId, childId, BadgeType.financialFreedomFlyer);
        } else {
          print(
            '⏳ "Save 100 SAR" badge: Need ${(100.0 - savingBalance).toStringAsFixed(2)} more SAR',
          );
        }
      } else {
        print('⚠️ Wallet not found for child $childId');
      }
    } catch (e) {
      print('❌ Error checking Financial Freedom Flyer: $e');
    }
  }

  /// Check and unlock Conqueror's Crown badge (first place in challenge)
  /// Condition: Win first place in challenge leaderboard (rank 1, unique winner)
  /// Note: This checks based on challenge task completions from last 7 days, matching the leaderboard logic
  static Future<void> checkConquerorsCrown(
    String parentId,
    String childId,
  ) async {
    try {
      // Get all children for this parent
      final childrenSnapshot = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .get();

      if (childrenSnapshot.docs.isEmpty) {
        print('⚠️ No children found for parent $parentId');
        return;
      }

      // Calculate challenge completions for the week (matching leaderboard logic)
      final now = DateTime.now();
      var weekStart = now.subtract(Duration(days: now.weekday - 1));
      weekStart = DateTime(weekStart.year, weekStart.month, weekStart.day);

      final Map<String, Map<String, dynamic>> childChallengeData = {};

      for (var childDoc in childrenSnapshot.docs) {
        final childIdForCheck = childDoc.id;

        // Get completed challenge tasks (both 'done' and 'pending')
        final doneTasks = await _firestore
            .collection('Parents')
            .doc(parentId)
            .collection('Children')
            .doc(childIdForCheck)
            .collection('Tasks')
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'done')
            .get();

        final pendingTasks = await _firestore
            .collection('Parents')
            .doc(parentId)
            .collection('Children')
            .doc(childIdForCheck)
            .collection('Tasks')
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'pending')
            .get();

        // Combine both done and pending tasks
        final allCompletedTasks = [...doneTasks.docs, ...pendingTasks.docs];

        // Calculate score based on how fast they completed
        DateTime? earliestCompletion;
        int completedCount = 0;

        if (allCompletedTasks.isNotEmpty) {
          for (var taskDoc in allCompletedTasks) {
            final taskData = taskDoc.data();
            if (taskData['completedDate'] != null) {
              final completedDate = (taskData['completedDate'] as Timestamp)
                  .toDate();
              // Check if within last 7 days
              if (completedDate.isAfter(
                weekStart.subtract(const Duration(seconds: 1)),
              )) {
                if (earliestCompletion == null ||
                    completedDate.isBefore(earliestCompletion)) {
                  earliestCompletion = completedDate;
                }
                completedCount++;
              }
            }
          }
        }

        childChallengeData[childIdForCheck] = {
          'completedCount': completedCount,
          'earliestCompletion': earliestCompletion ?? DateTime.now(),
        };
      }

      // Sort: by count first, then by speed, then alphabetically
      final sorted = childChallengeData.entries.toList();
      sorted.sort((a, b) {
        final aCount = a.value['completedCount'] as int;
        final bCount = b.value['completedCount'] as int;

        // First sort by count (more completions = higher rank)
        if (bCount != aCount) {
          return bCount.compareTo(aCount);
        }
        // If both have tasks (count > 0), sort by earliest completion time (faster = higher rank)
        if (aCount > 0 && bCount > 0) {
          final aDate = a.value['earliestCompletion'] as DateTime;
          final bDate = b.value['earliestCompletion'] as DateTime;
          return aDate.compareTo(bDate);
        }
        // If both have 0 tasks, sort by childId (alphabetically)
        return a.key.compareTo(b.key);
      });

      if (sorted.isEmpty) return;

      print('📊 Checking "Win 1st in Challenge" badge');
      print('   Challenge leaderboard ranking (last 7 days):');
      for (int i = 0; i < sorted.length && i < 3; i++) {
        final isCurrentChild = sorted[i].key == childId;
        final count = sorted[i].value['completedCount'] as int;
        print(
          '   ${i + 1}. ${sorted[i].key == childId ? "YOU" : "Child"}: $count challenge task(s)${isCurrentChild ? " ⭐" : ""}',
        );
      }

      // Check if current child is first place
      if (sorted.first.key == childId) {
        final firstCount = sorted.first.value['completedCount'] as int;
        final secondCount = sorted.length > 1
            ? (sorted[1].value['completedCount'] as int)
            : 0;

        // Check if unique first place (no tie) and has at least 1 completion
        if ((sorted.length == 1 || firstCount > secondCount) &&
            firstCount > 0) {
          print('✅ Unlocking "Win 1st in Challenge" badge - condition met!');
          await unlockBadge(parentId, childId, BadgeType.conquerorsCrown);
        } else if (firstCount == 0) {
          print(
            '⏳ "Win 1st in Challenge" badge: First place but no challenge tasks completed yet',
          );
        } else {
          print(
            '⏳ "Win 1st in Challenge" badge: There is a tie for first place',
          );
        }
      } else {
        final currentRank = sorted.indexWhere((e) => e.key == childId) + 1;
        final currentCount =
            childChallengeData[childId]?['completedCount'] as int? ?? 0;
        final firstCount = sorted.first.value['completedCount'] as int;
        final needed = firstCount - currentCount + 1;
        print(
          '⏳ "Win 1st in Challenge" badge: Currently rank $currentRank with $currentCount task(s), need $needed more challenge task(s) to be first',
        );
      }
    } catch (e) {
      print('❌ Error checking Conqueror\'s Crown: $e');
    }
  }

  /// Check and unlock High-Priority Hero badge (4 high-priority tasks completed)
  /// Condition: Complete 4 high-priority tasks (status = 'done', priority = 'high')
  static Future<void> checkHighPriorityHero(
    String parentId,
    String childId,
  ) async {
    try {
      // Get all high-priority tasks with status 'done' (approved by parent)
      final tasksSnapshot = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Tasks')
          .where('status', isEqualTo: 'done')
          .where('priority', isEqualTo: 'high')
          .get();

      final completedHighPriorityTasksCount = tasksSnapshot.docs.length;
      print(
        '📊 Checking "High-Priority Hero" badge: $completedHighPriorityTasksCount high-priority tasks completed',
      );

      if (completedHighPriorityTasksCount >= 4) {
        print('✅ Unlocking "High-Priority Hero" badge - condition met!');
        await unlockBadge(parentId, childId, BadgeType.highPriorityHero);
      } else {
        print(
          '⏳ "High-Priority Hero" badge: Need ${4 - completedHighPriorityTasksCount} more high-priority tasks',
        );
      }
    } catch (e) {
      print('❌ Error checking High-Priority Hero: $e');
    }
  }

  /// Check and unlock Wishlist Fulfillment badge (5 wishlist items purchased)
  /// Condition: Purchase 5 wishlist items (isPurchased = true)
  static Future<void> checkWishlistFulfillment(
    String parentId,
    String childId,
  ) async {
    try {
      // Get all purchased wishlist items
      final wishlistSnapshot = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .where('isPurchased', isEqualTo: true)
          .get();

      final purchasedItemsCount = wishlistSnapshot.docs.length;
      print(
        '📊 Checking "Wishlist Fulfillment" badge: $purchasedItemsCount wishlist items purchased',
      );

      if (purchasedItemsCount >= 5) {
        print('✅ Unlocking "Wishlist Fulfillment" badge - condition met!');
        await unlockBadge(parentId, childId, BadgeType.wishlistFulfillment);
      } else {
        print(
          '⏳ "Wishlist Fulfillment" badge: Need ${5 - purchasedItemsCount} more wishlist items',
        );
      }
    } catch (e) {
      print('❌ Error checking Wishlist Fulfillment: $e');
    }
  }

  /// Check all badges (call this periodically)
  static Future<void> checkAllBadges(String parentId, String childId) async {
    await checkTenaciousTaskmaster(parentId, childId);
    await checkFinancialFreedomFlyer(parentId, childId);
    await checkConquerorsCrown(parentId, childId);
    await checkHighPriorityHero(parentId, childId);
    await checkWishlistFulfillment(parentId, childId);
  }

  /// Get progress for a badge (current progress and target)
  /// Returns a map with 'current', 'target', and 'progress' (0.0 to 1.0)
  static Future<Map<String, dynamic>> getBadgeProgress(
    String parentId,
    String childId,
    BadgeType badgeType,
  ) async {
    try {
      switch (badgeType) {
        case BadgeType.tenaciousTaskmaster:
          final tasksSnapshot = await _firestore
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .doc(childId)
              .collection('Tasks')
              .where('status', isEqualTo: 'done')
              .get();
          final current = tasksSnapshot.docs.length;
          const target = 10;
          return {
            'current': current,
            'target': target,
            'progress': (current / target).clamp(0.0, 1.0),
          };

        case BadgeType.financialFreedomFlyer:
          final wallet = await FirebaseService.getChildWallet(
            parentId,
            childId,
          );
          final current = wallet?.savingBalance ?? 0.0;
          const target = 100.0;
          return {
            'current': current,
            'target': target,
            'progress': (current / target).clamp(0.0, 1.0),
          };

        case BadgeType.highPriorityHero:
          final tasksSnapshot = await _firestore
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .doc(childId)
              .collection('Tasks')
              .where('status', isEqualTo: 'done')
              .where('priority', isEqualTo: 'high')
              .get();
          final current = tasksSnapshot.docs.length;
          const target = 4;
          return {
            'current': current,
            'target': target,
            'progress': (current / target).clamp(0.0, 1.0),
          };

        case BadgeType.wishlistFulfillment:
          final wishlistSnapshot = await _firestore
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .doc(childId)
              .collection('Wishlist')
              .where('isPurchased', isEqualTo: true)
              .get();
          final current = wishlistSnapshot.docs.length;
          const target = 5;
          return {
            'current': current,
            'target': target,
            'progress': (current / target).clamp(0.0, 1.0),
          };

        case BadgeType.conquerorsCrown:
          // For conqueror's crown, we show rank-based progress
          // Get all children for this parent
          final childrenSnapshot = await _firestore
              .collection('Parents')
              .doc(parentId)
              .collection('Children')
              .get();

          if (childrenSnapshot.docs.isEmpty) {
            return {
              'current': 0,
              'target': 1,
              'progress': 0.0,
              'isRankBased': true,
              'rank': 0,
              'totalPlayers': 0,
            };
          }

          // Calculate challenge completions for the week
          final now = DateTime.now();
          var weekStart = now.subtract(Duration(days: now.weekday - 1));
          weekStart = DateTime(weekStart.year, weekStart.month, weekStart.day);

          final Map<String, Map<String, dynamic>> childChallengeData = {};

          for (var childDoc in childrenSnapshot.docs) {
            final childIdForCheck = childDoc.id;

            final doneTasks = await _firestore
                .collection('Parents')
                .doc(parentId)
                .collection('Children')
                .doc(childIdForCheck)
                .collection('Tasks')
                .where('isChallenge', isEqualTo: true)
                .where('status', isEqualTo: 'done')
                .get();

            final pendingTasks = await _firestore
                .collection('Parents')
                .doc(parentId)
                .collection('Children')
                .doc(childIdForCheck)
                .collection('Tasks')
                .where('isChallenge', isEqualTo: true)
                .where('status', isEqualTo: 'pending')
                .get();

            final allCompletedTasks = [...doneTasks.docs, ...pendingTasks.docs];

            DateTime? earliestCompletion;
            int completedCount = 0;

            if (allCompletedTasks.isNotEmpty) {
              for (var taskDoc in allCompletedTasks) {
                final taskData = taskDoc.data();
                if (taskData['completedDate'] != null) {
                  final completedDate = (taskData['completedDate'] as Timestamp)
                      .toDate();
                  if (completedDate.isAfter(
                    weekStart.subtract(const Duration(seconds: 1)),
                  )) {
                    if (earliestCompletion == null ||
                        completedDate.isBefore(earliestCompletion)) {
                      earliestCompletion = completedDate;
                    }
                    completedCount++;
                  }
                }
              }
            }

            childChallengeData[childIdForCheck] = {
              'completedCount': completedCount,
              'earliestCompletion': earliestCompletion ?? DateTime.now(),
            };
          }

          // Sort by count, then by speed
          final sorted = childChallengeData.entries.toList();
          sorted.sort((a, b) {
            final aCount = a.value['completedCount'] as int;
            final bCount = b.value['completedCount'] as int;
            if (bCount != aCount) {
              return bCount.compareTo(aCount);
            }
            if (aCount > 0 && bCount > 0) {
              final aDate = a.value['earliestCompletion'] as DateTime;
              final bDate = b.value['earliestCompletion'] as DateTime;
              return aDate.compareTo(bDate);
            }
            return a.key.compareTo(b.key);
          });

          final currentRank = sorted.indexWhere((e) => e.key == childId) + 1;
          final totalPlayers = sorted.length;
          final currentCount =
              childChallengeData[childId]?['completedCount'] as int? ?? 0;
          final firstCount = sorted.isNotEmpty
              ? (sorted.first.value['completedCount'] as int)
              : 0;

          // Progress: 1.0 if rank 1 and unique, otherwise based on how close to first
          double progress = 0.0;
          if (currentRank == 1 && totalPlayers > 0) {
            // Check if unique first place (no tie)
            final secondCount = sorted.length > 1
                ? (sorted[1].value['completedCount'] as int)
                : 0;
            if (currentCount > secondCount && currentCount > 0) {
              progress = 1.0; // Unique first place
            } else if (currentCount > 0) {
              progress = 0.9; // Tied for first
            }
          } else if (firstCount > 0) {
            // Progress based on how close to first place
            progress = (currentCount / (firstCount + 1)).clamp(0.0, 0.99);
          }

          return {
            'current': currentCount,
            'target': firstCount + 1,
            'progress': progress,
            'isRankBased': true,
            'rank': currentRank,
            'totalPlayers': totalPlayers,
          };
      }
    } catch (e) {
      print('Error getting badge progress: $e');
      return {'current': 0, 'target': 1, 'progress': 0.0};
    }
  }
}
