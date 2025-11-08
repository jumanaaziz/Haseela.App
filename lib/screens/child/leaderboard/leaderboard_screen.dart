import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'leaderboard_entry.dart';
import '../../../models/child.dart';
import '../../../models/wallet.dart';
import '../../../models/transaction.dart' as app_transaction;
import '../../services/haseela_service.dart';
import '../../services/firebase_service.dart';
import 'dart:async';
import 'my_badge_view.dart';
import '../../services/badge_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String parentId;
  final String childId;

  const LeaderboardScreen({
    Key? key,
    required this.parentId,
    required this.childId,
  }) : super(key: key);

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry> _weeklyLeaderboardData = [];
  List<LeaderboardEntry> _monthlyLeaderboardData = [];
  bool _isLoadingWeekly = true;
  bool _isLoadingMonthly = true;
  bool _showMyBadge = false;
  bool _isWeekly = true; // Weekly filter selected by default
  bool _isMonthDropdownOpen = false; // Track dropdown state
  bool _isWeeklyChallengeDropdownOpen =
      false; // Weekly challenge dropdown state
  bool _isMonthlyChallengeDropdownOpen =
      false; // Monthly challenge dropdown state
  final HaseelaService _haseelaService = HaseelaService();
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  List<String> _availableChallenges =
      []; // List of challenge names for the week
  String?
  _selectedChallenge; // Selected challenge name for weekly (null = all challenges)
  List<String> _availableMonthlyChallenges =
      []; // List of challenge names for the selected month
  String?
  _selectedMonthlyChallenge; // Selected challenge name for monthly (null = all challenges)

  @override
  void initState() {
    super.initState();
    _loadWeeklyLeaderboard();
    _loadMonthlyLeaderboard();
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<LeaderboardEntry> get _leaderboardData {
    return _isWeekly ? _weeklyLeaderboardData : _monthlyLeaderboardData;
  }

  bool get _isLoading {
    return _isWeekly ? _isLoadingWeekly : _isLoadingMonthly;
  }

  // Normalize DateTime to first day of month at midnight for comparison
  DateTime _normalizeMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  // Get list of all months (current year) - normalized
  List<DateTime> get _availableMonths {
    final now = DateTime.now();
    final months = <DateTime>[];
    // Get all 12 months of the current year
    for (int month = 1; month <= 12; month++) {
      months.add(_normalizeMonth(DateTime(now.year, month, 1)));
    }
    // Show current month first, then previous months (most recent first), then future months
    final currentMonth = now.month;
    final currentMonthDate = _normalizeMonth(
      DateTime(now.year, currentMonth, 1),
    );
    final pastMonths =
        months.where((m) => m.isBefore(currentMonthDate)).toList()
          ..sort((a, b) => b.compareTo(a)); // Most recent past month first
    final futureMonths = months
        .where((m) => m.isAfter(currentMonthDate))
        .toList();

    return [currentMonthDate, ...pastMonths, ...futureMonths];
  }

  String _formatMonth(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[date.month - 1];
  }

  Future<void> _loadWeeklyLeaderboard() async {
    setState(() {
      _isLoadingWeekly = true;
    });

    try {
      // Get all children from the same parent
      final List<Child> children = await _haseelaService.getAllChildren(
        widget.parentId,
      );

      if (children.isEmpty) {
        setState(() {
          _weeklyLeaderboardData = [];
          _availableChallenges = [];
          _isLoadingWeekly = false;
        });
        return;
      }

      // Calculate challenge completions for the week (matching parent leaderboard logic)
      final now = DateTime.now();
      var weekStart = now.subtract(Duration(days: now.weekday - 1));
      weekStart = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      childTasksMap = {};
      final Set<String> challengeNamesSet = {};

      // First, get ALL challenge tasks (completed and not completed) to populate dropdown
      final allChallengeQueries = children.map((child) async {
        final allTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(widget.parentId)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .get();

        return {'childId': child.id, 'allTasks': allTasksSnapshot.docs};
      }).toList();

      final allChallengeResults = await Future.wait(allChallengeQueries);
      for (final result in allChallengeResults) {
        final allTasks =
            result['allTasks']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        for (final taskDoc in allTasks) {
          final taskName = taskDoc.data()['taskName'] as String? ?? '';
          if (taskName.isNotEmpty) {
            challengeNamesSet.add(taskName);
          }
        }
      }

      // Then, get completed tasks (pending or done) for leaderboard calculations
      // pending = child completed, waiting for approval
      // done = parent approved
      final taskQueries = children.map((child) async {
        final completedTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(widget.parentId)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', whereIn: ['pending', 'done'])
            .get();

        final filteredTasks = completedTasksSnapshot.docs.where((taskDoc) {
          final taskData = taskDoc.data();
          final completedDate = (taskData['completedDate'] as Timestamp?)
              ?.toDate();
          return completedDate != null &&
              completedDate.isAfter(
                weekStart.subtract(const Duration(seconds: 1)),
              );
        }).toList();

        return {'childId': child.id, 'tasks': filteredTasks};
      }).toList();

      final taskResults = await Future.wait(taskQueries);
      for (final result in taskResults) {
        final childId = result['childId'] as String;
        final tasks =
            result['tasks']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        childTasksMap[childId] = tasks;
      }

      final availableChallenges = challengeNamesSet.toList()..sort();
      String? selectedChallenge = _selectedChallenge;
      if (selectedChallenge != null &&
          !availableChallenges.contains(selectedChallenge)) {
        selectedChallenge = null;
        print(
          '⚠️ Selected challenge "$_selectedChallenge" no longer available, resetting',
        );
      }

      final Map<String, Map<String, dynamic>> childDataMap = {};

      // Parallelize wallet and transaction queries
      final dataQueries = children.map((child) async {
        final tasksForChild = childTasksMap[child.id] ?? [];
        final relevantTasks = selectedChallenge == null
            ? tasksForChild
            : tasksForChild.where((taskDoc) {
                final taskName = taskDoc.data()['taskName'] as String? ?? '';
                return taskName == selectedChallenge;
              }).toList();

        DateTime? earliestCompletion;
        final int completedCount = relevantTasks.length;

        for (final taskDoc in relevantTasks) {
          final completedDate = (taskDoc.data()['completedDate'] as Timestamp?)
              ?.toDate();
          if (completedDate == null) continue;
          if (earliestCompletion == null ||
              completedDate.isBefore(earliestCompletion)) {
            earliestCompletion = completedDate;
          }
        }

        // Fetch wallet and transactions in parallel
        final walletFuture = FirebaseService.getChildWallet(
          widget.parentId,
          child.id,
        );
        final transactionsFuture =
            FirebaseService.getChildTransactions(
              widget.parentId,
              child.id,
            ).catchError((e) {
              print('Error loading transactions for ${child.id}: $e');
              return <app_transaction.Transaction>[];
            });

        final results = await Future.wait([walletFuture, transactionsFuture]);
        final wallet = results[0] as Wallet?;
        final transactions = results[1];

        final totalSaved = wallet?.savingBalance ?? 0.0;
        final totalSpent = wallet?.spendingBalance ?? 0.0;

        final points = LeaderboardEntry.calculatePoints(totalSaved);
        final currentLevel = LeaderboardEntry.calculateLevel(totalSaved);
        final progress = LeaderboardEntry.calculateProgressToNextLevel(
          totalSaved,
        );

        List<RecentPurchase> recentPurchases = [];
        try {
          final spendingTransactions =
              (transactions as List<app_transaction.Transaction>)
                  .where(
                    (t) =>
                        t.type.toLowerCase() == 'spending' &&
                        t.fromWallet.toLowerCase() == 'spending',
                  )
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date));

          recentPurchases = spendingTransactions
              .take(3)
              .map(
                (t) => RecentPurchase(
                  description: t.description,
                  amount: t.amount,
                  date: t.date,
                ),
              )
              .toList();
        } catch (e) {
          print('Error processing transactions: $e');
        }

        final childName = '${child.firstName} ${child.lastName}'.trim();
        if (childName.isEmpty) return null;

        return {
          'childId': child.id,
          'child': child,
          'name': childName,
          'completedCount': completedCount,
          'earliestCompletion': earliestCompletion,
          'totalSaved': totalSaved,
          'totalSpent': totalSpent,
          'points': points,
          'currentLevel': currentLevel,
          'progress': progress,
          'recentPurchases': recentPurchases,
        };
      }).toList();

      final dataResults = await Future.wait(dataQueries);
      for (final result in dataResults) {
        if (result == null) continue;
        final childId = result['childId'] as String;
        childDataMap[childId] = result as Map<String, dynamic>;
      }

      // If a challenge is selected, only include children who completed that challenge
      final filteredEntries = selectedChallenge != null
          ? childDataMap.entries.where((entry) {
              final count = entry.value['completedCount'] as int;
              return count > 0;
            }).toList()
          : childDataMap.entries.toList();

      // Check if all children have no challenge completions
      final allHaveNoChallenges = filteredEntries.every((entry) {
        final count = entry.value['completedCount'] as int;
        return count == 0;
      });

      if (allHaveNoChallenges && filteredEntries.isNotEmpty) {
        // Sort alphabetically when no challenges
        filteredEntries.sort((a, b) {
          final aName = (a.value['name'] as String).toLowerCase();
          final bName = (b.value['name'] as String).toLowerCase();
          return aName.compareTo(bName);
        });
      } else {
        // Normal sorting when there are challenges - prioritize earliest completion
        filteredEntries.sort((a, b) {
          final aData = a.value;
          final bData = b.value;
          final aCount = aData['completedCount'] as int;
          final bCount = bData['completedCount'] as int;

          // First priority: children with completions rank above those without
          if (aCount > 0 && bCount == 0) {
            return -1; // a has completions, b doesn't - a comes first
          }
          if (aCount == 0 && bCount > 0) {
            return 1; // b has completions, a doesn't - b comes first
          }

          // Second priority: earliest completion date (first to complete is #1)
          if (aCount > 0 && bCount > 0) {
            final aDate = aData['earliestCompletion'] as DateTime?;
            final bDate = bData['earliestCompletion'] as DateTime?;
            if (aDate != null && bDate != null) {
              final dateComparison = aDate.compareTo(bDate);
              if (dateComparison != 0) {
                return dateComparison; // Earlier date comes first
              }
            } else if (aDate != null && bDate == null) {
              return -1; // a has date, b doesn't - a comes first
            } else if (aDate == null && bDate != null) {
              return 1; // b has date, a doesn't - b comes first
            }
          }

          // Third priority: number of completed challenges
          if (aCount != bCount) {
            return bCount.compareTo(aCount);
          }

          // Fourth priority: points
          final aPoints = aData['points'] as int;
          final bPoints = bData['points'] as int;
          if (aPoints != bPoints) {
            return bPoints.compareTo(aPoints);
          }

          // Fifth priority: level
          final aLevel = aData['currentLevel'] as int;
          final bLevel = bData['currentLevel'] as int;
          if (aLevel != bLevel) {
            return bLevel.compareTo(aLevel);
          }

          // Sixth priority: name (alphabetical)
          final aName = (aData['name'] as String).toLowerCase();
          final bName = (bData['name'] as String).toLowerCase();
          return aName.compareTo(bName);
        });
      }

      final List<LeaderboardEntry> entries = [];
      // Start ranking from 1 (even when no challenges)
      for (int i = 0; i < filteredEntries.length; i++) {
        final entry = filteredEntries[i];
        final data = entry.value;
        final child = data['child'] as Child;
        entries.add(
          LeaderboardEntry(
            id: entry.key,
            name: data['name'] as String,
            avatarUrl: child.avatar.isNotEmpty ? child.avatar : '',
            totalSaved: data['totalSaved'] as double,
            totalSpent: data['totalSpent'] as double,
            points: data['points'] as int,
            currentLevel: data['currentLevel'] as int,
            progressToNextLevel: data['progress'] as double,
            recentPurchases: data['recentPurchases'] as List<RecentPurchase>,
            rank: i + 1,
          ),
        );
      }

      if (entries.isNotEmpty &&
          entries[0].id == widget.childId &&
          entries[0].rank == 1) {
        final firstData = childDataMap[entries[0].id];
        final firstCount = (firstData?['completedCount'] as int?) ?? 0;
        final secondEntry = entries.length > 1 ? entries[1] : null;
        final secondData = secondEntry != null
            ? childDataMap[secondEntry.id]
            : null;
        final secondCount = (secondData?['completedCount'] as int?) ?? 0;

        if (entries.length == 1 ||
            (firstCount > secondCount && firstCount > 0)) {
          BadgeService.checkConquerorsCrown(widget.parentId, widget.childId);
        }
      }

      if (mounted) {
        setState(() {
          _weeklyLeaderboardData = entries;
          _availableChallenges = availableChallenges;
          _selectedChallenge = selectedChallenge;
          _isLoadingWeekly = false;
        });
      }
    } catch (e) {
      print('❌ Error loading weekly leaderboard data: $e');
      if (mounted) {
        setState(() {
          _weeklyLeaderboardData = [];
          _availableChallenges = [];
          _isLoadingWeekly = false;
        });
      }
    }
  }

  // Check if the selected month has any challenge tasks
  Future<bool> _monthHasChallenges(DateTime month) async {
    try {
      final monthStart = DateTime(month.year, month.month, 1);
      final monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

      // Get all children
      final List<Child> children = await _haseelaService.getAllChildren(
        widget.parentId,
      );

      // Check if any child has challenge tasks in this month - parallelize queries
      // Include both pending and done status (pending = completed by child, done = approved)
      final monthCheckQueries = children.map((child) async {
        final completedTasks = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(widget.parentId)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', whereIn: ['pending', 'done'])
            .get();

        for (final taskDoc in completedTasks.docs) {
          final taskData = taskDoc.data();
          final completedDate = (taskData['completedDate'] as Timestamp?)
              ?.toDate();
          if (completedDate == null) continue;
          if (completedDate.isAfter(
                monthStart.subtract(const Duration(seconds: 1)),
              ) &&
              completedDate.isBefore(
                monthEnd.add(const Duration(seconds: 1)),
              )) {
            return true;
          }
        }
        return false;
      }).toList();

      final monthCheckResults = await Future.wait(monthCheckQueries);
      return monthCheckResults.any((hasChallenge) => hasChallenge == true);
    } catch (e) {
      print('Error checking if month has challenges: $e');
      return false;
    }
  }

  Future<void> _loadMonthlyLeaderboard() async {
    setState(() {
      _isLoadingMonthly = true;
    });

    try {
      // First, verify that the selected month has challenges
      final hasChallenges = await _monthHasChallenges(_selectedMonth);

      if (!hasChallenges) {
        print(
          '⚠️ Selected month ${_formatMonth(_selectedMonth)} has no challenge tasks',
        );
        if (mounted) {
          setState(() {
            _monthlyLeaderboardData = [];
            _availableMonthlyChallenges = [];
            _selectedMonthlyChallenge = null;
            _isLoadingMonthly = false;
          });
        }
        return;
      }

      // Get all children from the same parent
      final List<Child> children = await _haseelaService.getAllChildren(
        widget.parentId,
      );

      if (children.isEmpty) {
        setState(() {
          _monthlyLeaderboardData = [];
          _availableMonthlyChallenges = [];
          _selectedMonthlyChallenge = null;
          _isLoadingMonthly = false;
        });
        return;
      }

      // Calculate challenge completions for the selected month (matching parent leaderboard logic)
      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final monthEnd = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        0,
        23,
        59,
        59,
      );
      final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      childTasksMap = {};
      final Set<String> challengeNamesSet = {};

      // First, get ALL challenge tasks (completed and not completed) to populate dropdown
      final allMonthlyChallengeQueries = children.map((child) async {
        final allTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(widget.parentId)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .get();

        return {'childId': child.id, 'allTasks': allTasksSnapshot.docs};
      }).toList();

      final allMonthlyChallengeResults = await Future.wait(
        allMonthlyChallengeQueries,
      );
      for (final result in allMonthlyChallengeResults) {
        final allTasks =
            result['allTasks']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        for (final taskDoc in allTasks) {
          final taskName = taskDoc.data()['taskName'] as String? ?? '';
          if (taskName.isNotEmpty) {
            challengeNamesSet.add(taskName);
          }
        }
      }

      // Then, get completed tasks (pending or done) for leaderboard calculations
      // pending = child completed, waiting for approval
      // done = parent approved
      final monthlyTaskQueries = children.map((child) async {
        final completedTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(widget.parentId)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', whereIn: ['pending', 'done'])
            .get();

        final filteredTasks = completedTasksSnapshot.docs.where((taskDoc) {
          final taskData = taskDoc.data();
          final completedDate = (taskData['completedDate'] as Timestamp?)
              ?.toDate();
          return completedDate != null &&
              completedDate.isAfter(
                monthStart.subtract(const Duration(seconds: 1)),
              ) &&
              completedDate.isBefore(monthEnd.add(const Duration(seconds: 1)));
        }).toList();

        return {'childId': child.id, 'tasks': filteredTasks};
      }).toList();

      final monthlyTaskResults = await Future.wait(monthlyTaskQueries);
      for (final result in monthlyTaskResults) {
        final childId = result['childId'] as String;
        final tasks =
            result['tasks']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        childTasksMap[childId] = tasks;
      }

      final availableMonthlyChallenges = challengeNamesSet.toList()..sort();
      String? selectedMonthlyChallenge = _selectedMonthlyChallenge;
      if (selectedMonthlyChallenge != null &&
          !availableMonthlyChallenges.contains(selectedMonthlyChallenge)) {
        selectedMonthlyChallenge = null;
        print(
          '⚠️ Selected monthly challenge "$_selectedMonthlyChallenge" no longer available, resetting',
        );
      }

      final Map<String, Map<String, dynamic>> childDataMap = {};

      // Parallelize wallet and transaction queries
      final monthlyDataQueries = children.map((child) async {
        final tasksForChild = childTasksMap[child.id] ?? [];
        final relevantTasks = selectedMonthlyChallenge == null
            ? tasksForChild
            : tasksForChild.where((taskDoc) {
                final taskName = taskDoc.data()['taskName'] as String? ?? '';
                return taskName == selectedMonthlyChallenge;
              }).toList();

        DateTime? earliestCompletion;
        final int completedCount = relevantTasks.length;

        for (final taskDoc in relevantTasks) {
          final completedDate = (taskDoc.data()['completedDate'] as Timestamp?)
              ?.toDate();
          if (completedDate == null) continue;
          if (earliestCompletion == null ||
              completedDate.isBefore(earliestCompletion)) {
            earliestCompletion = completedDate;
          }
        }

        // Fetch wallet and transactions in parallel
        final walletFuture = FirebaseService.getChildWallet(
          widget.parentId,
          child.id,
        );
        final transactionsFuture =
            FirebaseService.getChildTransactions(
              widget.parentId,
              child.id,
            ).catchError((e) {
              print('Error loading transactions for ${child.id}: $e');
              return <app_transaction.Transaction>[];
            });

        final results = await Future.wait([walletFuture, transactionsFuture]);
        final wallet = results[0] as Wallet?;
        final transactions = results[1];

        final totalSaved = wallet?.savingBalance ?? 0.0;
        final totalSpent = wallet?.spendingBalance ?? 0.0;

        final points = LeaderboardEntry.calculatePoints(totalSaved);
        final currentLevel = LeaderboardEntry.calculateLevel(totalSaved);
        final progress = LeaderboardEntry.calculateProgressToNextLevel(
          totalSaved,
        );

        List<RecentPurchase> recentPurchases = [];
        try {
          final spendingTransactions =
              (transactions as List<app_transaction.Transaction>)
                  .where(
                    (t) =>
                        t.type.toLowerCase() == 'spending' &&
                        t.fromWallet.toLowerCase() == 'spending',
                  )
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date));

          recentPurchases = spendingTransactions
              .take(3)
              .map(
                (t) => RecentPurchase(
                  description: t.description,
                  amount: t.amount,
                  date: t.date,
                ),
              )
              .toList();
        } catch (e) {
          print('Error processing transactions: $e');
        }

        final childName = '${child.firstName} ${child.lastName}'.trim();
        if (childName.isEmpty) return null;

        return {
          'childId': child.id,
          'child': child,
          'name': childName,
          'completedCount': completedCount,
          'earliestCompletion': earliestCompletion,
          'totalSaved': totalSaved,
          'totalSpent': totalSpent,
          'points': points,
          'currentLevel': currentLevel,
          'progress': progress,
          'recentPurchases': recentPurchases,
        };
      }).toList();

      final monthlyDataResults = await Future.wait(monthlyDataQueries);
      for (final result in monthlyDataResults) {
        if (result == null) continue;
        final childId = result['childId'] as String;
        childDataMap[childId] = result as Map<String, dynamic>;
      }

      // If a challenge is selected, only include children who completed that challenge
      final filteredEntries = selectedMonthlyChallenge != null
          ? childDataMap.entries.where((entry) {
              final count = entry.value['completedCount'] as int;
              return count > 0;
            }).toList()
          : childDataMap.entries.toList();

      filteredEntries.sort((a, b) {
        final aData = a.value;
        final bData = b.value;
        final aCount = aData['completedCount'] as int;
        final bCount = bData['completedCount'] as int;

        // First priority: children with completions rank above those without
        if (aCount > 0 && bCount == 0) {
          return -1; // a has completions, b doesn't - a comes first
        }
        if (aCount == 0 && bCount > 0) {
          return 1; // b has completions, a doesn't - b comes first
        }

        // Second priority: earliest completion date (first to complete is #1)
        if (aCount > 0 && bCount > 0) {
          final aDate = aData['earliestCompletion'] as DateTime?;
          final bDate = bData['earliestCompletion'] as DateTime?;
          if (aDate != null && bDate != null) {
            final dateComparison = aDate.compareTo(bDate);
            if (dateComparison != 0) {
              return dateComparison; // Earlier date comes first
            }
          } else if (aDate != null && bDate == null) {
            return -1; // a has date, b doesn't - a comes first
          } else if (aDate == null && bDate != null) {
            return 1; // b has date, a doesn't - b comes first
          }
        }

        // Third priority: number of completed challenges
        if (aCount != bCount) {
          return bCount.compareTo(aCount);
        }

        // Fourth priority: points
        final aPoints = aData['points'] as int;
        final bPoints = bData['points'] as int;
        if (aPoints != bPoints) {
          return bPoints.compareTo(aPoints);
        }

        // Fifth priority: level
        final aLevel = aData['currentLevel'] as int;
        final bLevel = bData['currentLevel'] as int;
        if (aLevel != bLevel) {
          return bLevel.compareTo(aLevel);
        }

        // Sixth priority: name (alphabetical)
        final aName = (aData['name'] as String).toLowerCase();
        final bName = (bData['name'] as String).toLowerCase();
        return aName.compareTo(bName);
      });

      final List<LeaderboardEntry> entries = [];
      for (int i = 0; i < filteredEntries.length; i++) {
        final entry = filteredEntries[i];
        final data = entry.value;
        final child = data['child'] as Child;
        entries.add(
          LeaderboardEntry(
            id: entry.key,
            name: data['name'] as String,
            avatarUrl: child.avatar.isNotEmpty ? child.avatar : '',
            totalSaved: data['totalSaved'] as double,
            totalSpent: data['totalSpent'] as double,
            points: data['points'] as int,
            currentLevel: data['currentLevel'] as int,
            progressToNextLevel: data['progress'] as double,
            recentPurchases: data['recentPurchases'] as List<RecentPurchase>,
            rank: i + 1,
          ),
        );
      }

      if (entries.isNotEmpty &&
          entries[0].id == widget.childId &&
          entries[0].rank == 1) {
        final firstData = childDataMap[entries[0].id];
        final firstCount = (firstData?['completedCount'] as int?) ?? 0;
        final secondEntry = entries.length > 1 ? entries[1] : null;
        final secondData = secondEntry != null
            ? childDataMap[secondEntry.id]
            : null;
        final secondCount = (secondData?['completedCount'] as int?) ?? 0;

        if (entries.length == 1 ||
            (firstCount > secondCount && firstCount > 0)) {
          BadgeService.checkConquerorsCrown(widget.parentId, widget.childId);
        }
      }

      if (mounted) {
        setState(() {
          _monthlyLeaderboardData = entries;
          _availableMonthlyChallenges = availableMonthlyChallenges;
          _selectedMonthlyChallenge = selectedMonthlyChallenge;
          _isLoadingMonthly = false;
        });
      }
    } catch (e) {
      print('❌ Error loading monthly leaderboard data: $e');
      if (mounted) {
        setState(() {
          _monthlyLeaderboardData = [];
          _availableMonthlyChallenges = [];
          _isLoadingMonthly = false;
        });
      }
    }
  }

  LeaderboardEntry? get _currentUserEntry {
    try {
      return _leaderboardData.firstWhere((entry) => entry.id == widget.childId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF643FDB)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _showMyBadge
                  ? MyBadgeView(
                      entry: _currentUserEntry,
                      parentId: widget.parentId,
                      childId: widget.childId,
                    )
                  : RefreshIndicator(
                      onRefresh: _isWeekly
                          ? _loadWeeklyLeaderboard
                          : _loadMonthlyLeaderboard,
                      child: _buildLeaderboardContent(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardContent() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          SizedBox(height: 16.h),
          // Filter Buttons - Always visible at top
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                _buildFilterButton('Weekly', true),
                SizedBox(width: 16.w),
                _buildFilterButton('Month', false),
              ],
            ),
          ),

          // Challenge selector dropdown (only show when weekly view is selected)
          if (_isWeekly && _availableChallenges.isNotEmpty) ...[
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _buildChallengeDropdown(),
            ),
          ],

          // Month selector dropdown (only show when monthly view is selected)
          if (!_isWeekly) ...[
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _buildMonthDropdown(),
            ),
          ],

          // Challenge selector dropdown for monthly view (only show when monthly view is selected and challenges are available)
          if (!_isWeekly && _availableMonthlyChallenges.isNotEmpty) ...[
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _buildMonthlyChallengeDropdown(),
            ),
          ],

          // Show empty state or leaderboard data
          if (_leaderboardData.isEmpty)
            _buildEmptyState()
          else ...[
            SizedBox(height: 16.h),
            _buildBarChartView(),
          ],
        ],
      ),
    );
  }

  Widget _buildBarChartView() {
    if (_leaderboardData.isEmpty) return SizedBox.shrink();

    // Check if all children have no challenge completions (weekly only)
    final hasNoChallenges = _isWeekly && _leaderboardData.isNotEmpty;
    bool allHaveNoChallenges = false;
    if (hasNoChallenges) {
      // Check if all entries have 0 challenge completions by checking if they're sorted alphabetically
      // We can detect this by checking if the first entry's rank is 1 and all have same challenge count
      // Actually, we need to check the data - let's use a simpler approach
      // If weekly and we have data, check if all have rank starting from 1 and sorted alphabetically
      // For now, we'll check if there are any challenges available
      allHaveNoChallenges =
          _availableChallenges.isEmpty && _leaderboardData.isNotEmpty;
    }

    // If no challenges in weekly view, show message
    if (allHaveNoChallenges && _isWeekly) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 40.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Center(
            child: Text(
              'No challenges in this week',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B7280),
                fontFamily: 'SPProText',
              ),
            ),
          ),
        ),
      );
    }
    final topThree = _leaderboardData.length >= 3
        ? _leaderboardData.take(3).toList()
        : _leaderboardData;
    final otherPlayers = _leaderboardData.length > 3
        ? _leaderboardData.skip(3).toList()
        : <LeaderboardEntry>[];

    return Column(
      children: [
        // User Rank Banner
        if (_currentUserEntry != null) ...[
          _buildUserRankBanner(_currentUserEntry!),
          SizedBox(height: 24.h),
        ],
        // Podium for Top 3
        if (topThree.isNotEmpty) _buildPodium(topThree),
        if (topThree.isNotEmpty || otherPlayers.isNotEmpty)
          SizedBox(height: 24.h),
        // List for Rank 4+
        if (otherPlayers.isNotEmpty) ..._buildOtherPlayersList(otherPlayers),
        SizedBox(height: 100.h), // Space for bottom nav
      ],
    );
  }

  Widget _buildFilterButton(String label, bool isWeeklyButton) {
    final isSelected = isWeeklyButton == _isWeekly;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isWeekly = isWeeklyButton;
          // Reset challenge selection when switching views
          if (!isWeeklyButton) {
            _selectedChallenge = null;
          } else {
            _selectedMonthlyChallenge = null;
          }
          _isWeeklyChallengeDropdownOpen = false;
          _isMonthlyChallengeDropdownOpen = false;
          _isMonthDropdownOpen = false;
        });
        // Reload data when switching views
        if (isWeeklyButton) {
          _loadWeeklyLeaderboard();
        } else {
          _loadMonthlyLeaderboard();
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF643FDB) : Colors.transparent,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontFamily: 'SPProText',
          ),
        ),
      ),
    );
  }

  Widget _buildUserRankBanner(LeaderboardEntry entry) {
    final totalPlayers = _leaderboardData.length;
    final percentage = totalPlayers > 0
        ? ((totalPlayers - entry.rank + 1) / totalPlayers * 100).round()
        : 0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9500),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '#${entry.rank}',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFF9500),
                    fontFamily: 'SPProText',
                  ),
                ),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Text(
                'You are doing better than $percentage% of other players!',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFamily: 'SPProText',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodium(List<LeaderboardEntry> topThree) {
    // Ensure we have entries for positions 1, 2, 3
    final first = topThree.isNotEmpty ? topThree[0] : null;
    final second = topThree.length > 1 ? topThree[1] : null;
    final third = topThree.length > 2 ? topThree[2] : null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        children: [
          // Avatars and names above podium
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 2nd place (left)
              if (second != null)
                Expanded(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          _buildAvatar(second, 60.w, false),
                          Positioned(
                            top: -8.h,
                            child: Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4.r,
                                  ),
                                ],
                              ),
                              child: Text(
                                '2',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF643FDB),
                                  fontFamily: 'SPProText',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        second.name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1C1243),
                          fontFamily: 'SPProText',
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF643FDB),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          '${second.points} QP',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: 'SPProText',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(child: SizedBox()),
              SizedBox(width: 8.w),
              // 1st place (center)
              if (first != null)
                Expanded(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          _buildAvatar(first, 80.w, true),
                          Positioned(
                            top: -8.h,
                            child: Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4.r,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.workspace_premium,
                                size: 24.sp,
                                color: const Color(0xFFFFD700),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        first.name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1C1243),
                          fontFamily: 'SPProText',
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF643FDB),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          '${first.points} QP',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: 'SPProText',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(child: SizedBox()),
              SizedBox(width: 8.w),
              // 3rd place (right)
              if (third != null)
                Expanded(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          _buildAvatar(third, 60.w, false),
                          Positioned(
                            top: -8.h,
                            child: Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4.r,
                                  ),
                                ],
                              ),
                              child: Text(
                                '3',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF643FDB),
                                  fontFamily: 'SPProText',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        third.name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1C1243),
                          fontFamily: 'SPProText',
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF643FDB),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          '${third.points} QP',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: 'SPProText',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(child: SizedBox()),
            ],
          ),
          SizedBox(height: 16.h),
          // Podium visual
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 2nd place podium (medium height)
              if (second != null)
                Expanded(
                  child: Container(
                    height: 100.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF643FDB).withOpacity(0.3),
                          const Color(0xFF643FDB).withOpacity(0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12.r),
                        topRight: Radius.circular(12.r),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '2',
                        style: TextStyle(
                          fontSize: 48.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'SPProText',
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(child: SizedBox()),
              SizedBox(width: 4.w),
              // 1st place podium (tallest)
              if (first != null)
                Expanded(
                  child: Container(
                    height: 140.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF643FDB).withOpacity(0.3),
                          const Color(0xFF643FDB).withOpacity(0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12.r),
                        topRight: Radius.circular(12.r),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '1',
                        style: TextStyle(
                          fontSize: 48.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'SPProText',
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(child: SizedBox()),
              SizedBox(width: 4.w),
              // 3rd place podium (lowest)
              if (third != null)
                Expanded(
                  child: Container(
                    height: 80.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF643FDB).withOpacity(0.3),
                          const Color(0xFF643FDB).withOpacity(0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12.r),
                        topRight: Radius.circular(12.r),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '3',
                        style: TextStyle(
                          fontSize: 48.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'SPProText',
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(LeaderboardEntry entry, double size, bool isFirst) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3.w),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: ClipOval(
        child: entry.avatarUrl.isNotEmpty
            ? Image.network(
                entry.avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: Icon(
                      Icons.person,
                      size: size * 0.5,
                      color: Colors.grey[600],
                    ),
                  );
                },
              )
            : Container(
                color: Colors.grey[300],
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: Colors.grey[600],
                ),
              ),
      ),
    );
  }

  List<Widget> _buildOtherPlayersList(List<LeaderboardEntry> players) {
    return [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8.r,
                offset: Offset(0, 2.h),
              ),
            ],
          ),
          child: Column(
            children: players.asMap().entries.map((entryMap) {
              final entry = entryMap.value;
              final index = entryMap.key;
              final isCurrentUser = entry.id == widget.childId;
              final isLast = index == players.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 16.h),
                child: _buildListEntry(entry, isCurrentUser),
              );
            }).toList(),
          ),
        ),
      ),
    ];
  }

  Widget _buildListEntry(LeaderboardEntry entry, bool isCurrentUser) {
    return Row(
      children: [
        Container(
          width: 32.w,
          height: 32.w,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6B7280),
                fontFamily: 'SPProText',
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isCurrentUser
                  ? const Color(0xFF643FDB)
                  : Colors.grey[300]!,
              width: 2.w,
            ),
          ),
          child: ClipOval(
            child: entry.avatarUrl.isNotEmpty
                ? Image.network(
                    entry.avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: Icon(
                          Icons.person,
                          size: 20.sp,
                          color: Colors.grey[600],
                        ),
                      );
                    },
                  )
                : Container(
                    color: Colors.grey[300],
                    child: Icon(
                      Icons.person,
                      size: 20.sp,
                      color: Colors.grey[600],
                    ),
                  ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            entry.name + (isCurrentUser ? ' (You)' : ''),
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: isCurrentUser
                  ? const Color(0xFF643FDB)
                  : const Color(0xFF1C1243),
              fontFamily: 'SPProText',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${entry.points} points',
          style: TextStyle(
            fontSize: 14.sp,
            color: const Color(0xFF6B7280),
            fontFamily: 'SPProText',
          ),
        ),
      ],
    );
  }

  Widget _buildMonthDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected month button (always visible)
        GestureDetector(
          onTap: () {
            setState(() {
              _isMonthDropdownOpen = !_isMonthDropdownOpen;
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatMonth(_selectedMonth),
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF643FDB),
                      fontFamily: 'SPProText',
                    ),
                  ),
                ),
                Icon(
                  _isMonthDropdownOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xFF643FDB),
                  size: 24.sp,
                ),
              ],
            ),
          ),
        ),

        // Dropdown list (only show when open)
        if (_isMonthDropdownOpen) ...[
          SizedBox(height: 8.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Column(
              children: _availableMonths.map((DateTime month) {
                final normalized = _normalizeMonth(month);
                final selectedNormalized = _normalizeMonth(_selectedMonth);
                final isSelected = selectedNormalized == normalized;

                return GestureDetector(
                  onTap: () async {
                    final newNormalized = _normalizeMonth(month);
                    final currentSelected = _normalizeMonth(_selectedMonth);

                    // Only load if it's a different month
                    if (newNormalized != currentSelected) {
                      setState(() {
                        _selectedMonth = newNormalized;
                        _selectedMonthlyChallenge =
                            null; // Reset challenge when month changes
                        _isLoadingMonthly = true;
                        _isMonthDropdownOpen =
                            false; // Close dropdown after selection
                        _monthlyLeaderboardData = []; // Clear previous data
                      });
                      await _loadMonthlyLeaderboard();
                    } else {
                      // Close dropdown even if same month is selected
                      setState(() {
                        _isMonthDropdownOpen = false;
                      });
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF643FDB).withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      _formatMonth(normalized),
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? const Color(0xFF643FDB)
                            : const Color(0xFF1C1243),
                        fontFamily: 'SPProText',
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChallengeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected challenge button (always visible)
        GestureDetector(
          onTap: () {
            setState(() {
              _isWeeklyChallengeDropdownOpen = !_isWeeklyChallengeDropdownOpen;
              if (_isWeeklyChallengeDropdownOpen) {
                _isMonthlyChallengeDropdownOpen = false;
              }
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedChallenge ?? 'Select Challenge',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF643FDB),
                      fontFamily: 'SPProText',
                    ),
                  ),
                ),
                Icon(
                  _isWeeklyChallengeDropdownOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xFF643FDB),
                  size: 24.sp,
                ),
              ],
            ),
          ),
        ),

        // Dropdown list (only show when open)
        if (_isWeeklyChallengeDropdownOpen) ...[
          SizedBox(height: 8.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Column(
              children: _availableChallenges.map((String challengeName) {
                final isSelected = _selectedChallenge == challengeName;

                return GestureDetector(
                  onTap: () async {
                    setState(() {
                      _isWeeklyChallengeDropdownOpen = false;
                    });
                    if (_selectedChallenge != challengeName) {
                      setState(() {
                        _selectedChallenge = challengeName;
                      });
                      await _loadWeeklyLeaderboard();
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF643FDB).withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      challengeName,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? const Color(0xFF643FDB)
                            : const Color(0xFF1C1243),
                        fontFamily: 'SPProText',
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMonthlyChallengeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected challenge button (always visible)
        GestureDetector(
          onTap: () {
            setState(() {
              _isMonthlyChallengeDropdownOpen =
                  !_isMonthlyChallengeDropdownOpen;
              if (_isMonthlyChallengeDropdownOpen) {
                _isWeeklyChallengeDropdownOpen = false;
              }
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedMonthlyChallenge ?? 'Select Challenge',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF643FDB),
                      fontFamily: 'SPProText',
                    ),
                  ),
                ),
                Icon(
                  _isMonthlyChallengeDropdownOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xFF643FDB),
                  size: 24.sp,
                ),
              ],
            ),
          ),
        ),

        // Dropdown list (only show when open)
        if (_isMonthlyChallengeDropdownOpen) ...[
          SizedBox(height: 8.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: Column(
              children: _availableMonthlyChallenges.map((String challengeName) {
                final isSelected = _selectedMonthlyChallenge == challengeName;

                return GestureDetector(
                  onTap: () async {
                    setState(() {
                      _isMonthlyChallengeDropdownOpen = false;
                    });
                    if (_selectedMonthlyChallenge != challengeName) {
                      setState(() {
                        _selectedMonthlyChallenge = challengeName;
                      });
                      await _loadMonthlyLeaderboard();
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF643FDB).withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      challengeName,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? const Color(0xFF643FDB)
                            : const Color(0xFF1C1243),
                        fontFamily: 'SPProText',
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    // Different message for weekly vs monthly view
    if (_isWeekly) {
      // Check if a challenge is selected
      if (_selectedChallenge != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 80.sp,
                color: Colors.grey[400],
              ),
              SizedBox(height: 16.h),
              Text(
                'No completions for "${_selectedChallenge}"',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  fontFamily: 'SPProText',
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),
              Text(
                'No children have completed this challenge yet',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[500],
                  fontFamily: 'SPProText',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80.sp, color: Colors.grey[400]),
            SizedBox(height: 16.h),
            Text(
              'No siblings in the list',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                fontFamily: 'SPProText',
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Add more siblings to start competing!',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[500],
                fontFamily: 'SPProText',
              ),
            ),
          ],
        ),
      );
    } else {
      // Monthly view: show message about no challenges in selected month
      // Check if a challenge is selected
      if (_selectedMonthlyChallenge != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 80.sp,
                color: Colors.grey[400],
              ),
              SizedBox(height: 16.h),
              Text(
                'No completions for "${_selectedMonthlyChallenge}"',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  fontFamily: 'SPProText',
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),
              Text(
                'No children have completed this challenge in ${_formatMonth(_selectedMonth)}',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[500],
                  fontFamily: 'SPProText',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 80.sp,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16.h),
            Text(
              'No challenges in ${_formatMonth(_selectedMonth)}',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                fontFamily: 'SPProText',
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'There were no challenge task completions in this month',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[500],
                fontFamily: 'SPProText',
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _showMyBadge ? 'My Badge' : 'Leaderboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1C1243),
                fontFamily: 'SPProText',
              ),
            ),
          ),
          // Toggle Button
          IconButton(
            icon: Icon(
              _showMyBadge ? Icons.bar_chart : Icons.emoji_events,
              color: const Color(0xFF643FDB),
              size: 24.sp,
            ),
            onPressed: () {
              setState(() {
                _showMyBadge = !_showMyBadge;
              });
            },
            tooltip: _showMyBadge ? 'View Leaderboard' : 'View My Badge',
          ),
        ],
      ),
    );
  }
}
