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

  // Get list of months (only current year) - normalized
  List<DateTime> get _availableMonths {
    final now = DateTime.now();
    final months = <DateTime>[];
    // Get all months from January to current month of the current year
    for (int month = 1; month <= now.month; month++) {
      months.add(_normalizeMonth(DateTime(now.year, month, 1)));
    }
    // Reverse to show current month first
    return months.reversed.toList();
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

  /// Load weekly leaderboard (last 7 days, sorted by count then speed)
  Future<void> _loadWeeklyLeaderboard() async {
    setState(() => _isLoadingWeekly = true);

    try {
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

        // Get completed challenge tasks (both 'done' and 'pending' - pending means child submitted, parent might approve later)
        // We'll filter by completedDate in code since Firestore can't do OR queries easily
        final doneTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'done')
            .get();

        final pendingTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'pending')
            .get();

        print('     - Done tasks: ${doneTasksSnapshot.docs.length}');
        print('     - Pending tasks: ${pendingTasksSnapshot.docs.length}');

        // Combine both done and pending tasks
        final allCompletedTasks = [
          ...doneTasksSnapshot.docs,
          ...pendingTasksSnapshot.docs,
        ];

        // Calculate score based on how fast they completed (earliest completion wins)
        DateTime? earliestCompletion;
        int completedCount = 0;

        if (allCompletedTasks.isNotEmpty) {
          for (var taskDoc in allCompletedTasks) {
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

        // Always add entry, even if completedCount is 0
        print(
          '   ✓ Adding entry: $childName with $completedCount completion(s)',
        );
        entriesMap[childId] = LeaderboardEntry(
          childId: childId,
          childName: childName,
          childAvatar: childAvatar,
          completedCount: completedCount,
          earliestCompletion: earliestCompletion ?? DateTime.now(),
        );
      }

      // Convert to list and sort: by count first, then by speed for those with tasks, then alphabetically for those with 0 tasks
      final entries = entriesMap.values.toList();
      entries.sort((a, b) {
        // First sort by count (more completions = higher rank)
        if (b.completedCount != a.completedCount) {
          return b.completedCount.compareTo(a.completedCount);
        }
        // If both have tasks (count > 0), sort by earliest completion time (faster = higher rank)
        if (a.completedCount > 0 && b.completedCount > 0) {
          return a.earliestCompletion.compareTo(b.earliestCompletion);
        }
        // If both have 0 tasks, sort alphabetically by name
        return a.childName.toLowerCase().compareTo(b.childName.toLowerCase());
      });

      print('✅ Weekly leaderboard loaded: ${entries.length} entries');

      setState(() {
        _weeklyEntries = entries;
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

  /// Load monthly leaderboard (selected month, sorted by count then speed)
  Future<void> _loadMonthlyLeaderboard() async {
    setState(() => _isLoadingMonthly = true);

    try {
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

        // Get completed challenge tasks (both 'done' and 'pending')
        final doneTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'done')
            .get();

        final pendingTasksSnapshot = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(childId)
            .collection("Tasks")
            .where('isChallenge', isEqualTo: true)
            .where('status', isEqualTo: 'pending')
            .get();

        // Combine both done and pending tasks
        final allCompletedTasks = [
          ...doneTasksSnapshot.docs,
          ...pendingTasksSnapshot.docs,
        ];

        // Calculate score based on how fast they completed (earliest completion wins)
        DateTime? earliestCompletion;
        int completedCount = 0;

        if (allCompletedTasks.isNotEmpty) {
          for (var taskDoc in allCompletedTasks) {
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

        // Always add entry, even if completedCount is 0
        entriesMap[childId] = LeaderboardEntry(
          childId: childId,
          childName: childName,
          childAvatar: childAvatar,
          completedCount: completedCount,
          earliestCompletion: earliestCompletion ?? DateTime.now(),
        );
      }

      // Convert to list and sort: by count first, then by speed for those with tasks, then alphabetically for those with 0 tasks
      final entries = entriesMap.values.toList();
      entries.sort((a, b) {
        // First sort by count (more completions = higher rank)
        if (b.completedCount != a.completedCount) {
          return b.completedCount.compareTo(a.completedCount);
        }
        // If both have tasks (count > 0), sort by earliest completion time (faster = higher rank)
        if (a.completedCount > 0 && b.completedCount > 0) {
          return a.earliestCompletion.compareTo(b.earliestCompletion);
        }
        // If both have 0 tasks, sort alphabetically by name
        return a.childName.toLowerCase().compareTo(b.childName.toLowerCase());
      });

      setState(() {
        _monthlyEntries = entries;
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

    if (_weeklyEntries.isEmpty) {
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
                'No challenge completions yet',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Create a challenge task to see the weekly leaderboard',
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

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        children: [
          _buildTopThreeLeaderboard(_weeklyEntries),
          if (_weeklyEntries.length > 3) ...[
            SizedBox(height: 24.h),
            ...List.generate(_weeklyEntries.length - 3, (index) {
              final entry = _weeklyEntries[index + 3];
              return _buildLeaderboardItem(entry: entry, rank: index + 4);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyView() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month selector dropdown
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DateTime>(
                value: _normalizeMonth(_selectedMonth),
                isExpanded: true,
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: const Color(0xFF7C3AED),
                  size: 28.sp,
                ),
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
                items: _availableMonths.map((DateTime month) {
                  final normalized = _normalizeMonth(month);
                  return DropdownMenuItem<DateTime>(
                    value: normalized,
                    child: Text(_formatMonth(normalized)),
                  );
                }).toList(),
                onChanged: (DateTime? newMonth) {
                  if (newMonth != null) {
                    setState(() {
                      _selectedMonth = _normalizeMonth(newMonth);
                    });
                    _loadMonthlyLeaderboard();
                  }
                },
              ),
            ),
          ),

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
          else
            Column(
              children: [
                _buildTopThreeLeaderboard(_monthlyEntries),
                if (_monthlyEntries.length > 3) ...[
                  SizedBox(height: 24.h),
                  ...List.generate(_monthlyEntries.length - 3, (index) {
                    final entry = _monthlyEntries[index + 3];
                    return _buildLeaderboardItem(entry: entry, rank: index + 4);
                  }),
                ],
              ],
            ),
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
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        // Top 3 on pedestals
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 2nd place with silver medal
            if (entries.length > 1)
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // The card
                    _buildTopThreeCard(
                      entry: entries[1],
                      rank: 2,
                      color: const Color(0xFFFF9800),
                    ),
                    // Silver medal icon positioned at the top of the card
                    Positioned(
                      top: -24.h,
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC0C0C0), // Silver color
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC0C0C0).withOpacity(0.6),
                              blurRadius: 15,
                              offset: Offset(0, 4),
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.workspace_premium,
                          color: Colors.white,
                          size: 28.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (entries.length > 1) SizedBox(width: 8.w),
            // 1st place with gold medal
            Expanded(
              flex: 2,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // The card
                  _buildTopThreeCard(
                    entry: entries[0],
                    rank: 1,
                    color: const Color(0xFF7C3AED),
                    isFirst: true,
                  ),
                  // Gold medal icon positioned at the top of the card
                  Positioned(
                    top: -24.h,
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.6),
                            blurRadius: 15,
                            offset: Offset(0, 4),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.workspace_premium,
                        color: Colors.white,
                        size: 28.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (entries.length > 2) SizedBox(width: 8.w),
            // 3rd place with bronze medal
            if (entries.length > 2)
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // The card
                    _buildTopThreeCard(
                      entry: entries[2],
                      rank: 3,
                      color: const Color(0xFFFF9800),
                    ),
                    // Bronze medal icon positioned at the top of the card
                    Positioned(
                      top: -24.h,
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCD7F32), // Bronze color
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFCD7F32).withOpacity(0.6),
                              blurRadius: 15,
                              offset: Offset(0, 4),
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.workspace_premium,
                          color: Colors.white,
                          size: 28.sp,
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
    required LeaderboardEntry entry,
    required int rank,
    required Color color,
    bool isFirst = false,
  }) {
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
          // Rank badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),

          // Avatar
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
