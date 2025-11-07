import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../widgets/custom_bottom_nav.dart';
import 'parent_profile_screen.dart';
import 'task_management_screen.dart';
import 'parent_wishlist_screen.dart';

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
  List<LeaderboardEntry> _weeklyEntries = [];
  List<LeaderboardEntry> _monthlyEntries = [];
  bool _isLoadingWeekly = true;
  bool _isLoadingMonthly = true;
  bool _isMonthDropdownOpen = false; // Track dropdown state

  // Month selector for monthly leaderboard - normalize to first day of month at midnight
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

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

  // Check if any challenge tasks exist (not just completed ones)
  Future<bool> _hasChallengeTasks() async {
    try {
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid)
          .collection("Children")
          .get();

      for (var childDoc in childrenSnapshot.docs) {
        final challengeTasks = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childDoc.id)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .limit(1)
            .get();

        if (challengeTasks.docs.isNotEmpty) {
          return true; // Found at least one challenge task
        }
      }
      return false; // No challenge tasks found
    } catch (e) {
      print('Error checking for challenge tasks: $e');
      return false;
    }
  }

  /// Load weekly leaderboard (last 7 days, sorted by count then speed)
  Future<void> _loadWeeklyLeaderboard() async {
    setState(() => _isLoadingWeekly = true);

    try {
      // First check if any challenge tasks exist
      final hasChallenges = await _hasChallengeTasks();
      if (!hasChallenges) {
        setState(() {
          _weeklyEntries = [];
          _isLoadingWeekly = false;
        });
        return;
      }

      // Get start of current week (last 7 days)
      final now = DateTime.now();
      final weekStart = now.subtract(const Duration(days: 7));

      print('🔍 Loading weekly leaderboard from: $weekStart to $now');

      // Get all children
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid)
          .collection("Children")
          .get();

      if (childrenSnapshot.docs.isEmpty) {
        setState(() {
          _weeklyEntries = [];
          _isLoadingWeekly = false;
        });
        return;
      }

      final Map<String, LeaderboardEntry> entriesMap = {};

      // For each child, get their completed challenge tasks from last 7 days
      for (var childDoc in childrenSnapshot.docs) {
        final childData = childDoc.data() as Map<String, dynamic>?;
        final childId = childDoc.id;
        final childName = childData?['firstName'] ?? 'Unknown';
        final childAvatar = childData?['avatar'] as String?;

        print('   Checking child: $childId ($childName)');

        // Get ALL challenge tasks first to debug
        final allChallengeTasks = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .get();

        print(
          '     Found ${allChallengeTasks.docs.length} challenge task(s) total',
        );

        // Only get approved tasks (status = 'done') - children only appear after parent approval
        final approvedTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'done')
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
        entriesMap[childId] = LeaderboardEntry(
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
      final entriesWithTasks = allEntries.where((e) => e.completedCount > 0).toList();
      final entriesWithZeroTasks = allEntries.where((e) => e.completedCount == 0).toList();
      
      // Sort children with tasks by count first, then by completion time (earliest = higher rank)
      // Ranking is based on when child completed (completedDate), NOT when parent approved
      if (entriesWithTasks.isNotEmpty) {
        entriesWithTasks.sort((a, b) {
          // First sort by count (more completions = higher rank)
          if (b.completedCount != a.completedCount) {
            return b.completedCount.compareTo(a.completedCount);
          }
          // If same count, sort by earliest completion time (who completed first = higher rank)
          // This uses completedDate (when child completed), not approval time
          return a.earliestCompletion.compareTo(b.earliestCompletion);
        });
      }
      
      // Sort children with 0 tasks alphabetically
      entriesWithZeroTasks.sort((a, b) => a.childName.toLowerCase().compareTo(b.childName.toLowerCase()));
      
      // Combine: entries with tasks first (for top 3), then entries with 0 tasks (for list)
      final sortedEntries = [...entriesWithTasks, ...entriesWithZeroTasks];

      print('✅ Weekly leaderboard loaded: ${sortedEntries.length} entries (${entriesWithTasks.length} with tasks, ${entriesWithZeroTasks.length} with 0 tasks)');

      setState(() {
        _weeklyEntries = sortedEntries;
        _isLoadingWeekly = false;
      });
    } catch (e) {
      print('Error loading weekly leaderboard: $e');
      setState(() {
        _weeklyEntries = [];
        _isLoadingWeekly = false;
      });
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

  /// Load monthly leaderboard (selected month, sorted by count then speed)
  Future<void> _loadMonthlyLeaderboard() async {
    setState(() => _isLoadingMonthly = true);

    try {
      // First, verify that the selected month has challenges
      final hasChallenges = await _monthHasChallenges(_selectedMonth);

      if (!hasChallenges) {
        print(
          '⚠️ Selected month ${_formatMonth(_selectedMonth)} has no challenge tasks',
        );
        setState(() {
          _monthlyEntries = [];
          _isLoadingMonthly = false;
        });
        return;
      }

      // Get start and end of selected month
      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final monthEnd = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        0,
        23,
        59,
        59,
      );

      print(
        '🔍 Loading monthly leaderboard for: ${_formatMonth(_selectedMonth)}',
      );
      print('   Date range: $monthStart to $monthEnd');

      // Get all children
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid)
          .collection("Children")
          .get();

      if (childrenSnapshot.docs.isEmpty) {
        setState(() {
          _monthlyEntries = [];
          _isLoadingMonthly = false;
        });
        return;
      }

      final Map<String, LeaderboardEntry> entriesMap = {};

      // For each child, get their completed challenge tasks this month
      for (var childDoc in childrenSnapshot.docs) {
        final childData = childDoc.data() as Map<String, dynamic>?;
        final childId = childDoc.id;
        final childName = childData?['firstName'] ?? 'Unknown';
        final childAvatar = childData?['avatar'] as String?;

        // Only get approved tasks (status = 'done') - children only appear after parent approval
        final approvedTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'done')
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
        entriesMap[childId] = LeaderboardEntry(
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
      final entriesWithTasks = allEntries.where((e) => e.completedCount > 0).toList();
      final entriesWithZeroTasks = allEntries.where((e) => e.completedCount == 0).toList();
      
      // Sort children with tasks by count first, then by completion time (earliest = higher rank)
      // Ranking is based on when child completed (completedDate), NOT when parent approved
      if (entriesWithTasks.isNotEmpty) {
        entriesWithTasks.sort((a, b) {
          // First sort by count (more completions = higher rank)
          if (b.completedCount != a.completedCount) {
            return b.completedCount.compareTo(a.completedCount);
          }
          // If same count, sort by earliest completion time (who completed first = higher rank)
          // This uses completedDate (when child completed), not approval time
          return a.earliestCompletion.compareTo(b.earliestCompletion);
        });
      }
      
      // Sort children with 0 tasks alphabetically
      entriesWithZeroTasks.sort((a, b) => a.childName.toLowerCase().compareTo(b.childName.toLowerCase()));
      
      // Combine: entries with tasks first (for top 3), then entries with 0 tasks (for list)
      final sortedEntries = [...entriesWithTasks, ...entriesWithZeroTasks];

      print('✅ Monthly leaderboard loaded: ${sortedEntries.length} entries (${entriesWithTasks.length} with tasks, ${entriesWithZeroTasks.length} with 0 tasks)');

      setState(() {
        _monthlyEntries = sortedEntries;
        _isLoadingMonthly = false;
      });
    } catch (e) {
      print('Error loading monthly leaderboard: $e');
      setState(() {
        _monthlyEntries = [];
        _isLoadingMonthly = false;
      });
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 3,
        onTap: (i) => _onNavTap(context, i),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false, // Remove back arrow
        centerTitle: true,
        title: Text(
          'Leaderboard',
          style: TextStyle(
            color: const Color(0xFF1E293B),
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.h),
          child: Container(
            height: 1.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFFE2E8F0),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20.h),

              // Toggle buttons (Weekly / Monthly)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildToggleButton(
                        label: 'Weekly Leaderboard',
                        isSelected: _isWeeklyView,
                        onTap: () {
                          setState(() {
                            _isWeeklyView = true;
                          });
                          _loadWeeklyLeaderboard();
                        },
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _buildToggleButton(
                        label: 'Monthly Leaderboard',
                        isSelected: !_isWeeklyView,
                        onTap: () {
                          setState(() {
                            _isWeeklyView = false;
                          });
                          _loadMonthlyLeaderboard();
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24.h),

              // Show Weekly or Monthly based on toggle
              _isWeeklyView ? _buildWeeklyView() : _buildMonthlyView(),

              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyView() {
    if (_isLoadingWeekly) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(40.h),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF7C3AED),
              ),
            ),
          ),
        ),
      );
    }

    // Check if challenge tasks exist using FutureBuilder
    return FutureBuilder<bool>(
      future: _hasChallengeTasks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40.h),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF7C3AED),
                  ),
                ),
              ),
            ),
          );
        }

        final hasChallenges = snapshot.data ?? false;
        if (!hasChallenges) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Container(
          padding: EdgeInsets.all(32.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          child: Column(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 64.sp,
                color: const Color(0xFF94A3B8),
              ),
              SizedBox(height: 16.h),
              Text(
                'No challenge task yet',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Start a challenge task to see the weekly leaderboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
        }

        // Don't show "no completions" message here - if challenge exists, show children with 0 tasks
        // The "no challenge task" message is already handled by the FutureBuilder above

        // Separate entries: those with tasks (for top 3) and all entries (for list)
        final entriesWithTasks = _weeklyEntries.where((e) => e.completedCount > 0).toList();
        final allEntries = _weeklyEntries; // All entries for the list below
        
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Column(
            children: [
              // Top 3: Only show children who have completed tasks
              _buildTopThreeLeaderboard(entriesWithTasks),
              // List below: Show all remaining children (those not in top 3)
              if (allEntries.length > 3 || entriesWithTasks.isEmpty) ...[
                SizedBox(height: 24.h),
                // If no one has completed tasks, show all children alphabetically
                if (entriesWithTasks.isEmpty) ...[
                  ...List.generate(allEntries.length, (index) {
                    final entry = allEntries[index];
                    return _buildLeaderboardItem(entry: entry, rank: index + 1);
                  }),
                ] else ...[
                  // Show remaining children (those not in top 3)
                  ...List.generate(allEntries.length - 3, (index) {
                    final entry = allEntries[index + 3];
                    return _buildLeaderboardItem(entry: entry, rank: index + 4);
                  }),
                ],
              ],
            ],
          ),
        );
      },
    );
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
                      color: const Color(0xFF7C3AED),
                    ),
                  ),
                ),
                Icon(
                  _isMonthDropdownOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xFF7C3AED),
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
                          ? const Color(0xFF7C3AED).withOpacity(0.15)
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
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFF1E293B),
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

  Widget _buildMonthlyView() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month selector list
          _buildMonthSelectorList(),

          SizedBox(height: 24.h),

          // Leaderboard content
          if (_isLoadingMonthly)
            Center(
              child: Padding(
                padding: EdgeInsets.all(40.h),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF7C3AED),
                  ),
                ),
              ),
            )
          else if (_monthlyEntries.isEmpty)
            Container(
              padding: EdgeInsets.all(32.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 64.sp,
                    color: const Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'No challenge tasks in ${_formatMonth(_selectedMonth)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'There were no challenge task completions in this month',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Separate entries: those with tasks (for top 3) and all entries (for list)
            Builder(
              builder: (context) {
                final entriesWithTasks = _monthlyEntries.where((e) => e.completedCount > 0).toList();
                final allEntries = _monthlyEntries; // All entries for the list below
                
                return Column(
                  children: [
                    // Top 3: Only show children who have completed tasks
                    _buildTopThreeLeaderboard(entriesWithTasks),
                    // List below: Show all remaining children (those not in top 3)
                    if (allEntries.length > 3 || entriesWithTasks.isEmpty) ...[
                      SizedBox(height: 24.h),
                      // If no one has completed tasks, show all children alphabetically
                      if (entriesWithTasks.isEmpty) ...[
                        ...List.generate(allEntries.length, (index) {
                          final entry = allEntries[index];
                          return _buildLeaderboardItem(entry: entry, rank: index + 1);
                        }),
                      ] else ...[
                        // Show remaining children (those not in top 3)
                        ...List.generate(allEntries.length - 3, (index) {
                          final entry = allEntries[index + 3];
                          return _buildLeaderboardItem(entry: entry, rank: index + 4);
                        }),
                      ],
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7C3AED) : Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopThreeLeaderboard(List<LeaderboardEntry> entries) {
    // Always show 3 ranks, even if only one child
    final first = entries.isNotEmpty ? entries[0] : null;
    final second = entries.length > 1 ? entries[1] : null;
    final third = entries.length > 2 ? entries[2] : null;

    return Column(
      children: [
        // Top 3 on pedestals
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 2nd place (left) - always show, even if empty
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // The card
                  _buildTopThreeCard(
                    entry: second,
                    rank: 2,
                    color: const Color(0xFFFF9800), // Orange
                  ),
                  // Star badge with #2
                  Positioned(
                    top: -20.h,
                    child: Container(
                      width: 40.w,
                      height: 40.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC0C0C0), // Always silver color, even when empty
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          // LED glow effect - multiple layers for depth
                          BoxShadow(
                            color: const Color(0xFFC0C0C0).withOpacity(0.8),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: Offset(0, 0),
                          ),
                          BoxShadow(
                            color: const Color(0xFFC0C0C0).withOpacity(0.6),
                            blurRadius: 10,
                            spreadRadius: 1,
                            offset: Offset(0, 0),
                          ),
                          BoxShadow(
                            color: const Color(0xFFC0C0C0).withOpacity(0.4),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            color: Colors.white,
                            size: 14.sp,
                          ),
                          SizedBox(height: 1.h),
                          Text(
                            '#2',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            // 1st place (center) - always show
            Expanded(
              flex: 2,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // The card
                  _buildTopThreeCard(
                    entry: first,
                    rank: 1,
                    color: const Color(0xFF7C3AED), // Purple
                    isFirst: true,
                  ),
                  // Star badge with #1
                  Positioned(
                    top: -20.h,
                    child: Container(
                      width: 48.w,
                      height: 48.w,
                      decoration: BoxDecoration(
                        color: first != null ? Colors.yellow[700]! : Colors.grey[300]!,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          // LED glow effect - multiple layers for depth
                          BoxShadow(
                            color: (first != null ? Colors.yellow[700]! : Colors.grey[400]!).withOpacity(0.9),
                            blurRadius: 20,
                            spreadRadius: 3,
                            offset: Offset(0, 0),
                          ),
                          BoxShadow(
                            color: (first != null ? Colors.yellow[600]! : Colors.grey[300]!).withOpacity(0.7),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: Offset(0, 0),
                          ),
                          BoxShadow(
                            color: (first != null ? Colors.yellow : Colors.grey[200]!).withOpacity(0.5),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            color: Colors.white,
                            size: 16.sp,
                          ),
                          SizedBox(height: 1.h),
                          Text(
                            '#1',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            // 3rd place (right) - always show, even if empty
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // The card
                  _buildTopThreeCard(
                    entry: third,
                    rank: 3,
                    color: const Color(0xFFFF9800), // Orange
                  ),
                  // Star badge with #3
                  Positioned(
                    top: -20.h,
                    child: Container(
                      width: 40.w,
                      height: 40.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCD7F32), // Always bronze color, even when empty
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          // LED glow effect - multiple layers for depth
                          BoxShadow(
                            color: const Color(0xFFCD7F32).withOpacity(0.8),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: Offset(0, 0),
                          ),
                          BoxShadow(
                            color: const Color(0xFFCD7F32).withOpacity(0.6),
                            blurRadius: 10,
                            spreadRadius: 1,
                            offset: Offset(0, 0),
                          ),
                          BoxShadow(
                            color: const Color(0xFFCD7F32).withOpacity(0.4),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            color: Colors.white,
                            size: 14.sp,
                          ),
                          SizedBox(height: 1.h),
                          Text(
                            '#3',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopThreeCard({
    LeaderboardEntry? entry,
    required int rank,
    required Color color,
    bool isFirst = false,
  }) {
    // If no entry, show empty card
    if (entry == null) {
      final height = isFirst ? 240.h : 200.h;
      return Container(
        height: height,
        padding: EdgeInsets.only(
          left: 6.w,
          right: 6.w,
          top: 18.h,
          bottom: 10.h,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: color.withOpacity(0.5), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Empty avatar circle
            CircleAvatar(
              radius: isFirst ? 56.r : 46.r,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Icon(
                Icons.person,
                color: Colors.white.withOpacity(0.3),
                size: isFirst ? 40.sp : 32.sp,
              ),
            ),
            SizedBox(height: 12.h),
            // Empty name
            Text(
              '',
              style: TextStyle(
                fontSize: isFirst ? 15.sp : 13.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 3.h),
            // Empty tasks
            Text(
              '',
              style: TextStyle(
                fontSize: isFirst ? 12.sp : 10.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    // Fixed heights to prevent overflow - increased slightly for first place to accommodate crown
    final height = isFirst ? 240.h : 200.h;
    final avatarSize = isFirst ? 56.r : 46.r;

    return Container(
      height: height,
      padding: EdgeInsets.only(
        left: 6.w,
        right: 6.w,
        top: isFirst
            ? 18.h
            : 18.h, // Extra top padding for all top 3 to make room for medals
        bottom: 10.h,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar (rank badge is now at the top with star)
          Flexible(
            child: CircleAvatar(
              radius: avatarSize,
              backgroundColor: Colors.white.withOpacity(0.3),
              backgroundImage: entry.childAvatar != null
                  ? NetworkImage(entry.childAvatar!)
                  : null,
              child: entry.childAvatar == null
                  ? Text(
                      entry.childName.isNotEmpty
                          ? entry.childName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: isFirst ? 22.sp : 18.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),

          // Name and Score section
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Name - using Flexible with FittedBox
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.w),
                      child: Text(
                        entry.childName,
                        style: TextStyle(
                          fontSize: isFirst ? 15.sp : 13.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 3.h),
                // Score
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.w),
                      child: Text(
                        '${entry.completedCount} ${entry.completedCount == 1 ? "task" : "tasks"}',
                        style: TextStyle(
                          fontSize: isFirst ? 12.sp : 10.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardItem({
    required LeaderboardEntry entry,
    required int rank,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank
          Container(
            width: 40.w,
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          SizedBox(width: 16.w),
          // Avatar
          CircleAvatar(
            radius: 24.r,
            backgroundColor: const Color(0xFF7C3AED).withOpacity(0.1),
            backgroundImage: entry.childAvatar != null
                ? NetworkImage(entry.childAvatar!)
                : null,
            child: entry.childAvatar == null
                ? Text(
                    entry.childName.isNotEmpty
                        ? entry.childName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF7C3AED),
                    ),
                  )
                : null,
          ),
          SizedBox(width: 16.w),
          // Name
          Expanded(
            child: Text(
              entry.childName,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 12.w),
          // Points
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              '${entry.completedCount} ${entry.completedCount == 1 ? "task" : "tasks"}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7C3AED),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LeaderboardEntry {
  final String childId;
  final String childName;
  final String? childAvatar;
  final int completedCount;
  final DateTime earliestCompletion;

  LeaderboardEntry({
    required this.childId,
    required this.childName,
    this.childAvatar,
    required this.completedCount,
    required this.earliestCompletion,
  });
}
