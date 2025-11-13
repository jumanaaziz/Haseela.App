import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../widgets/custom_bottom_nav.dart';
import 'parent_profile_screen.dart';
import 'task_management_screen.dart';
import 'parent_wishlist_screen.dart';
import '../child/leaderboard/leaderboard_entry.dart';
import '../../models/child.dart';
import '../../models/wallet.dart';
import '../../models/transaction.dart' as app_transaction;
import '../services/haseela_service.dart';
import '../services/firebase_service.dart';

class ParentLeaderboardEntry {
  final String childId;
  final String childName;
  final String? childAvatar;
  final int completedCount;
  final DateTime earliestCompletion;
  final double totalSaved;
  final double totalSpent;
  final int points;
  final int currentLevel;
  final double progressToNextLevel;
  final List<RecentPurchase> recentPurchases;

  ParentLeaderboardEntry({
    required this.childId,
    required this.childName,
    this.childAvatar,
    required this.completedCount,
    required this.earliestCompletion,
    required this.totalSaved,
    required this.totalSpent,
    required this.points,
    required this.currentLevel,
    required this.progressToNextLevel,
    required this.recentPurchases,
  });
}

class ParentLeaderboardScreen extends StatefulWidget {
  const ParentLeaderboardScreen({super.key});

  @override
  State<ParentLeaderboardScreen> createState() =>
      _ParentLeaderboardScreenState();
}

class _ParentLeaderboardScreenState extends State<ParentLeaderboardScreen> {
  // ✅ Always use the signed-in parent's UID
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  bool _isWeeklyView = true; // Toggle between Weekly and Monthly
  List<ParentLeaderboardEntry> _weeklyEntries = [];
  List<ParentLeaderboardEntry> _monthlyEntries = [];
  bool _isLoadingWeekly = true;
  bool _isLoadingMonthly = true;
  bool _isMonthDropdownOpen = false; // Track dropdown state
  bool _isWeeklyChallengeDropdownOpen =
      false; // Weekly challenge dropdown state
  bool _isMonthlyChallengeDropdownOpen =
      false; // Monthly challenge dropdown state
  final HaseelaService _haseelaService = HaseelaService();

  // Month selector for monthly leaderboard - normalize to first day of month at midnight
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

  /// Load weekly leaderboard (matching child leaderboard logic)
  Future<void> _loadWeeklyLeaderboard() async {
    setState(() {
      _isLoadingWeekly = true;
    });

    try {
      // Get all children from the same parent
      final List<Child> children = await _haseelaService.getAllChildren(_uid);

      if (children.isEmpty) {
        setState(() {
          _weeklyEntries = [];
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
            .doc(_uid)
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
            .doc(_uid)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', whereIn: ['pending', 'done'])
            .get();

        print('     - Approved tasks: ${approvedTasksSnapshot.docs.length}');

        // Calculate score based on when child completed the task (completedDate)
        // NOT based on when parent approved it - ranking is by completion time
        DateTime? earliestCompletion;
        int completedCount = 0;

        if (approvedTasksSnapshot.docs.isNotEmpty) {
          for (var taskDoc in approvedTasksSnapshot.docs) {
            final taskData = taskDoc.data() as Map<String, dynamic>?;

            // Debug: print task details
            print(
              '     Task ${taskDoc.id}: status=${taskData?['status']}, completedDate=${taskData?['completedDate']}',
            );

            if (taskData != null && taskData['completedDate'] != null) {
              final completedDate = (taskData['completedDate'] as Timestamp)
                  .toDate();

              // Check if within last 7 days
              if (completedDate.isAfter(
                weekStart.subtract(const Duration(seconds: 1)),
              )) {
                print('       ✓ Completed within last 7 days: $completedDate');
                if (earliestCompletion == null ||
                    completedDate.isBefore(earliestCompletion)) {
                  earliestCompletion = completedDate;
                }
                completedCount++;
              } else {
                print(
                  '       ✗ Completed outside 7-day window: $completedDate',
                );
              }
            } else {
              print('       ⚠️ No completedDate field');
            }
          }
        }

        // Always add entry, even if child has 0 tasks
        // This allows showing all children when challenge exists but no one completed yet
        print(
          '   ✓ Adding entry: $childName with $completedCount approved completion(s)',
        );
        entriesMap[childId] = ParentLeaderboardEntry(
          childId: childId,
          childName: childName,
          childAvatar: childAvatar,
          completedCount: completedCount,
          earliestCompletion: earliestCompletion ?? DateTime.now(),
        );
      }

      // Convert to list and separate into two groups:
      // 1. Children with completed tasks (for top 3)
      // 2. All children (for the full list below)
      final allEntries = entriesMap.values.toList();
      final entriesWithTasks = allEntries
          .where((e) => e.completedCount > 0)
          .toList();
      final entriesWithZeroTasks = allEntries
          .where((e) => e.completedCount == 0)
          .toList();

      // Sort children with tasks by count first, then by completion time (earliest = higher rank)
      // Ranking is based on when child completed (completedDate), NOT when parent approved
      if (entriesWithTasks.isNotEmpty) {
        entriesWithTasks.sort((a, b) {
          // First sort by count (more completions = higher rank)
          final countCompare = b.completedCount.compareTo(a.completedCount);
          if (countCompare != 0) return countCompare;
          // If same count, sort by earliest completion time (who completed first = higher rank)
          // This uses completedDate (when child completed), not approval time
          final completionCompare =
              a.earliestCompletion.compareTo(b.earliestCompletion);
          if (completionCompare != 0) return completionCompare;
          // Final deterministic fallback: alphabetical by name
          return a.childName
              .toLowerCase()
              .compareTo(b.childName.toLowerCase());
        });
      }

      // Sort children with 0 tasks alphabetically
      entriesWithZeroTasks.sort(
        (a, b) =>
            a.childName.toLowerCase().compareTo(b.childName.toLowerCase()),
      );

      // Combine: entries with tasks first (for top 3), then entries with 0 tasks (for list)
      final sortedEntries = [...entriesWithTasks, ...entriesWithZeroTasks];

      print(
        '✅ Weekly leaderboard loaded: ${sortedEntries.length} entries (${entriesWithTasks.length} with tasks, ${entriesWithZeroTasks.length} with 0 tasks)',
      );

      setState(() {
        _weeklyEntries = sortedEntries;
        _isLoadingWeekly = false;
      });
    } catch (e) {
      print('❌ Error loading weekly leaderboard data: $e');
      if (mounted) {
        setState(() {
          _weeklyEntries = [];
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
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid)
          .collection("Children")
          .get();

      // Check if any child has approved challenge tasks in this month
      // Only count approved tasks (status = 'done'), not pending ones
      for (var childDoc in childrenSnapshot.docs) {
        final approvedTasks = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childDoc.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'done')
            .get();

        // Check if any approved task was completed in this month
        for (var taskDoc in approvedTasks.docs) {
          final taskData = taskDoc.data();
          if (taskData['completedDate'] != null) {
            final completedDate = (taskData['completedDate'] as Timestamp)
                .toDate();
            if (completedDate.isAfter(
                  monthStart.subtract(const Duration(seconds: 1)),
                ) &&
                completedDate.isBefore(
                  monthEnd.add(const Duration(seconds: 1)),
                )) {
              return true; // Found at least one approved challenge in this month
            }
          }
        }
      }
      return false; // No challenges found in this month
    } catch (e) {
      print('Error checking if month has challenges: $e');
      return false;
    }
  }

  /// Load monthly leaderboard (matching child leaderboard logic)
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
            _monthlyEntries = [];
            _availableMonthlyChallenges = [];
            _selectedMonthlyChallenge = null;
            _isLoadingMonthly = false;
          });
        }
        return;
      }

      // Get all children from the same parent
      final List<Child> children = await _haseelaService.getAllChildren(_uid);

      if (children.isEmpty) {
        setState(() {
          _monthlyEntries = [];
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
            .doc(_uid)
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
            .doc(_uid)
            .collection("Children")
            .doc(child.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', whereIn: ['pending', 'done'])
            .get();

        // Calculate score based on when child completed the task (completedDate)
        // NOT based on when parent approved it - ranking is by completion time
        DateTime? earliestCompletion;
        int completedCount = 0;

        if (approvedTasksSnapshot.docs.isNotEmpty) {
          for (var taskDoc in approvedTasksSnapshot.docs) {
            final taskData = taskDoc.data() as Map<String, dynamic>?;
            if (taskData != null && taskData['completedDate'] != null) {
              final completedDate = (taskData['completedDate'] as Timestamp)
                  .toDate();

              // Check if within selected month
              if (completedDate.isAfter(
                    monthStart.subtract(const Duration(seconds: 1)),
                  ) &&
                  completedDate.isBefore(
                    monthEnd.add(const Duration(seconds: 1)),
                  )) {
                print('       ✓ Completed in selected month: $completedDate');
                if (earliestCompletion == null ||
                    completedDate.isBefore(earliestCompletion)) {
                  earliestCompletion = completedDate;
                }
                completedCount++;
              }
            }
          }
        }

        // Always add entry, even if child has 0 tasks
        // This allows showing all children when challenge exists but no one completed yet
        entriesMap[childId] = ParentLeaderboardEntry(
          childId: childId,
          childName: childName,
          childAvatar: childAvatar,
          completedCount: completedCount,
          earliestCompletion: earliestCompletion ?? DateTime.now(),
        );
      }

      // Convert to list and separate into two groups:
      // 1. Children with completed tasks (for top 3)
      // 2. All children (for the full list below)
      final allEntries = entriesMap.values.toList();
      final entriesWithTasks = allEntries
          .where((e) => e.completedCount > 0)
          .toList();
      final entriesWithZeroTasks = allEntries
          .where((e) => e.completedCount == 0)
          .toList();

      // Sort children with tasks by count first, then by completion time (earliest = higher rank)
      // Ranking is based on when child completed (completedDate), NOT when parent approved
      if (entriesWithTasks.isNotEmpty) {
        entriesWithTasks.sort((a, b) {
          // First sort by count (more completions = higher rank)
          final countCompare = b.completedCount.compareTo(a.completedCount);
          if (countCompare != 0) return countCompare;
          // If same count, sort by earliest completion time (who completed first = higher rank)
          // This uses completedDate (when child completed), not approval time
          final completionCompare =
              a.earliestCompletion.compareTo(b.earliestCompletion);
          if (completionCompare != 0) return completionCompare;
          // Final deterministic fallback: alphabetical by name
          return a.childName
              .toLowerCase()
              .compareTo(b.childName.toLowerCase());
        });
      }

      // Sort children with 0 tasks alphabetically
      entriesWithZeroTasks.sort(
        (a, b) =>
            a.childName.toLowerCase().compareTo(b.childName.toLowerCase()),
      );

      // Combine: entries with tasks first (for top 3), then entries with 0 tasks (for list)
      final sortedEntries = [...entriesWithTasks, ...entriesWithZeroTasks];

      print(
        '✅ Monthly leaderboard loaded: ${sortedEntries.length} entries (${entriesWithTasks.length} with tasks, ${entriesWithZeroTasks.length} with 0 tasks)',
      );

      setState(() {
        _monthlyEntries = sortedEntries;
        _isLoadingMonthly = false;
      });
    } catch (e) {
      print('❌ Error loading monthly leaderboard data: $e');
      if (mounted) {
        setState(() {
          _monthlyEntries = [];
          _availableMonthlyChallenges = [];
          _isLoadingMonthly = false;
        });
      }
    }
  }

  void _onNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentProfileScreen()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TaskManagementScreen()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ParentWishlistScreen(parentId: _uid),
          ),
        );
        break;
      case 3:
        // Already on Leaderboard
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingWeekly && _isLoadingMonthly) {
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
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 3,
        onTap: (i) => _onNavTap(context, i),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'Leaderboard',
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1C1243),
            fontFamily: 'SPProText',
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _isWeeklyView
              ? _loadWeeklyLeaderboard
              : _loadMonthlyLeaderboard,
          child: _buildLeaderboardContent(),
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
          if (_isWeeklyView && _availableChallenges.isNotEmpty) ...[
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _buildChallengeDropdown(),
            ),
          ],

          // Month selector dropdown (only show when monthly view is selected)
          if (!_isWeeklyView) ...[
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _buildMonthSelectorList(),
            ),
          ],

          // Challenge selector dropdown for monthly view
          if (!_isWeeklyView && _availableMonthlyChallenges.isNotEmpty) ...[
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: _buildMonthlyChallengeDropdown(),
            ),
          ],

          // Show empty state or leaderboard data
          if (_isWeeklyView && _weeklyEntries.isEmpty)
            _buildEmptyState()
          else if (!_isWeeklyView && _monthlyEntries.isEmpty)
            _buildEmptyState()
          else ...[
            SizedBox(height: 16.h),
            _buildBarChartView(),
          ],
        ],
      ),
    );
  }

  List<ParentLeaderboardEntry> get _leaderboardData {
    return _isWeeklyView ? _weeklyEntries : _monthlyEntries;
  }

  Widget _buildFilterButton(String label, bool isWeeklyButton) {
    final isSelected = isWeeklyButton == _isWeeklyView;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isWeeklyView = isWeeklyButton;
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

  Widget _buildChallengeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  Widget _buildBarChartView() {
    if (_leaderboardData.isEmpty) return SizedBox.shrink();

    final hasNoChallenges = _isWeeklyView && _leaderboardData.isNotEmpty;
    bool allHaveNoChallenges = false;
    if (hasNoChallenges) {
      allHaveNoChallenges =
          _availableChallenges.isEmpty && _leaderboardData.isNotEmpty;
    }

    if (allHaveNoChallenges && _isWeeklyView) {
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
        : <ParentLeaderboardEntry>[];

    return Column(
      children: [
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

  Widget _buildPodium(List<ParentLeaderboardEntry> topThree) {
    final first = topThree.isNotEmpty ? topThree[0] : null;
    final second = topThree.length > 1 ? topThree[1] : null;
    final third = topThree.length > 2 ? topThree[2] : null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                        second.childName,
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
                        first.childName,
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
                        third.childName,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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

  Widget _buildAvatar(ParentLeaderboardEntry entry, double size, bool isFirst) {
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
        child: entry.childAvatar != null && entry.childAvatar!.isNotEmpty
            ? Image.network(
                entry.childAvatar!,
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

  List<Widget> _buildOtherPlayersList(List<ParentLeaderboardEntry> players) {
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
              final isLast = index == players.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 16.h),
                child: _buildListEntry(entry),
              );
            }).toList(),
          ),
        ),
      ),
    ];
  }

  Widget _buildListEntry(ParentLeaderboardEntry entry) {
    final rank = _leaderboardData.indexOf(entry) + 1;
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
              '$rank',
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
            border: Border.all(color: Colors.grey[300]!, width: 2.w),
          ),
          child: ClipOval(
            child: entry.childAvatar != null && entry.childAvatar!.isNotEmpty
                ? Image.network(
                    entry.childAvatar!,
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
            entry.childName,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1C1243),
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

  Widget _buildEmptyState() {
    if (_isWeeklyView) {
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

  Widget _buildMonthSelectorList() {
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
                        _isLoadingMonthly = true;
                        _isMonthDropdownOpen =
                            false; // Close dropdown after selection
                        _monthlyEntries = []; // Clear previous data
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
}
