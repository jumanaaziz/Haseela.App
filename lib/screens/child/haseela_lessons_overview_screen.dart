import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'haseela_lesson_details_screen.dart';
import '../child/child_home_screen.dart';
import '../auth_wrapper.dart';

class HaseelaLessonsOverviewScreen extends StatefulWidget {
  final String childName;
  final String childId;
  final String? parentId; // Make parentId optional for backward compatibility

  const HaseelaLessonsOverviewScreen({
    super.key,
    required this.childName,
    required this.childId,
    this.parentId,
  });

  @override
  State<HaseelaLessonsOverviewScreen> createState() =>
      _HaseelaLessonsOverviewScreenState();
}

class _HaseelaLessonsOverviewScreenState
    extends State<HaseelaLessonsOverviewScreen>
    with TickerProviderStateMixin {
  late AnimationController _floatingController;
  late Animation<double> _floatingAnimation;

  // Real progress data from Firestore
  int childLevel = 1; // Default level, will be updated from Firestore
  List<int> completedLessons = []; // List of completed lesson IDs
  final int totalLessons = 5;

  List<LessonLevel> get lessons => [
    LessonLevel(
      id: 1,
      title: "What are Riyals?",
      tagline: "Meet Haseel and learn about Saudi money!",
      icon: "🐇",
      gradient: [Color(0xFF10B981), Color(0xFF059669)],
      isUnlocked: childLevel >= 1,
      isCompleted: completedLessons.contains(1),
    ),
    LessonLevel(
      id: 2,
      title: "Earning Your Allowance",
      tagline: "Help Haseel earn riyals by doing chores!",
      icon: "💼",
      gradient: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      isUnlocked: childLevel >= 2,
      isCompleted: completedLessons.contains(2),
    ),
    LessonLevel(
      id: 3,
      title: "Saving for Dreams",
      tagline: "Build your riyal savings with Haseel!",
      icon: "🏦",
      gradient: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
      isUnlocked: childLevel >= 3,
      isCompleted: completedLessons.contains(3),
    ),
    LessonLevel(
      id: 4,
      title: "Sharing & Sadaqah",
      tagline: "Spread kindness with Haseel's help!",
      icon: "🤝",
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
      isUnlocked: childLevel >= 4,
      isCompleted: completedLessons.contains(4),
    ),
    LessonLevel(
      id: 5,
      title: "Smart Riyal Choices",
      tagline: "Make wise decisions with Haseel!",
      icon: "🧠",
      gradient: [Color(0xFFEC4899), Color(0xFFBE185D)],
      isUnlocked: childLevel >= 5,
      isCompleted: completedLessons.contains(5),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _floatingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _floatingAnimation = Tween<double>(begin: -10.0, end: 10.0).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );
    _floatingController.repeat(reverse: true);

    // Load child's level from Firestore
    _loadChildLevel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload data when returning to this screen
    _loadChildLevel();
  }

  void _loadChildLevel() async {
    try {
      String? parentId = widget.parentId;

      // If parentId is not provided, try to find it
      if (parentId == null) {
        // Try to find parent ID from child document in main Children collection
        DocumentSnapshot childDoc = await FirebaseFirestore.instance
            .collection('Children')
            .doc(widget.childId)
            .get();

        if (childDoc.exists) {
          Map<String, dynamic> childData =
              childDoc.data() as Map<String, dynamic>;
          if (childData['parent'] != null) {
            DocumentReference parentRef =
                childData['parent'] as DocumentReference;
            parentId = parentRef.id;
          }
        }
      }

      if (parentId != null) {
        // Load from Parents subcollection (primary source)
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('Parents')
            .doc(parentId)
            .collection('Children')
            .doc(widget.childId)
            .get();

        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          setState(() {
            childLevel = data['level'] ?? 1;
            completedLessons = List<int>.from(data['completedLessons'] ?? []);
          });
        }
      } else {
        // Fallback: try main Children collection
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('Children')
            .doc(widget.childId)
            .get();

        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          setState(() {
            childLevel = data['level'] ?? 1;
            completedLessons = List<int>.from(data['completedLessons'] ?? []);
          });
        }
      }
    } catch (e) {
      print('Error loading child level: $e');
      // Keep default level of 1 and empty completed lessons
    }
  }

  @override
  void dispose() {
    _floatingController.dispose();
    super.dispose();
  }

  Future<void> _navigateToChildHome() async {
    String? parentId = widget.parentId;

    // Try to get parentId from multiple sources
    if (parentId == null) {
      // First try: session service
      parentId = session.parentId;
      print('ParentId from session: $parentId');
    }

    if (parentId == null) {
      // Second try: fetch from Firestore using childId
      try {
        parentId = await _getParentIdFromChildId();
        print('ParentId from Firestore: $parentId');
      } catch (e) {
        print('Error fetching parentId from Firestore: $e');
      }
    }

    if (parentId == null) {
      // Third try: show error and navigate to auth wrapper
      print('Error: Could not retrieve parentId from any source');
      _showErrorAndNavigateToAuth();
      return;
    }

    Navigator.pop(context);
  }

  Future<String?> _getParentIdFromChildId() async {
    try {
      // Query the Children collection to find the parent
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('Children')
          .where('id', isEqualTo: widget.childId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data() as Map<String, dynamic>;

        // Check if parent field exists
        if (data.containsKey('parent')) {
          final parentField = data['parent'];
          if (parentField is String) {
            // Extract parentId from path like "Parents/parentId"
            if (parentField.contains('/')) {
              return parentField.split('/').last;
            }
            return parentField;
          } else if (parentField is DocumentReference) {
            return parentField.id;
          }
        }
      }

      // Alternative: try to find parent by searching through all parents
      QuerySnapshot parentsSnapshot = await FirebaseFirestore.instance
          .collection('Parents')
          .get();

      for (QueryDocumentSnapshot parentDoc in parentsSnapshot.docs) {
        QuerySnapshot childrenSnapshot = await FirebaseFirestore.instance
            .collection('Parents')
            .doc(parentDoc.id)
            .collection('Children')
            .where('id', isEqualTo: widget.childId)
            .limit(1)
            .get();

        if (childrenSnapshot.docs.isNotEmpty) {
          return parentDoc.id;
        }
      }

      return null;
    } catch (e) {
      print('Error in _getParentIdFromChildId: $e');
      return null;
    }
  }

  void _showErrorAndNavigateToAuth() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to load profile. Please log in again.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );

    // Navigate to auth wrapper as fallback
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AuthWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Disable hardware back button
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF8FAFC),
                const Color(0xFFF1F5F9),
                const Color(0xFFE2E8F0).withOpacity(0.3),
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Custom App Bar
                _buildCustomAppBar(),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 20.h,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Progress Header
                        _buildProgressHeader(),
                        SizedBox(height: 24.h),

                        // Lessons List
                        _buildLessonsList(),
                        SizedBox(height: 24.h),

                        // Floating Elements
                        _buildFloatingElements(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2), Color(0xFFF093FB)],
          stops: [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: IconButton(
              onPressed:
                  _navigateToChildHome, // Navigate to child home instead of back
              icon: Icon(
                Icons.home_rounded, // Change icon to home instead of back arrow
                color: Colors.white,
                size: 20.sp,
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Learning Journey',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Master money skills with Haseel! 🦉',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text('🦉', style: TextStyle(fontSize: 24.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeader() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.trending_up_rounded,
                  color: Colors.white,
                  size: 24.sp,
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progress Overview',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '${completedLessons.length} of $totalLessons lessons completed',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          // Progress Bar
          Container(
            height: 8.h,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (completedLessons.length / totalLessons).clamp(
                0.0,
                1.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '${((completedLessons.length / totalLessons) * 100).toInt()}% Complete',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Learning Levels',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        SizedBox(height: 16.h),
        ...lessons.asMap().entries.map((entry) {
          final index = entry.key;
          final lesson = entry.value;
          return Padding(
            padding: EdgeInsets.only(bottom: 16.h),
            child: _buildLessonCard(lesson, index),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildLessonCard(LessonLevel lesson, int index) {
    final isLocked = !lesson.isUnlocked;
    final isCompleted = lesson.isCompleted;
    final isCurrent = !isLocked && !isCompleted;

    return AnimatedBuilder(
      animation: _floatingAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, isCurrent ? _floatingAnimation.value : 0),
          child: Container(
            decoration: BoxDecoration(
              gradient: isLocked
                  ? LinearGradient(
                      colors: [
                        const Color(0xFF9CA3AF).withOpacity(0.3),
                        const Color(0xFF6B7280).withOpacity(0.3),
                      ],
                    )
                  : LinearGradient(
                      colors: lesson.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color: isLocked
                      ? Colors.grey.withOpacity(0.2)
                      : lesson.gradient[0].withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20.r),
                onTap: isLocked
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HaseelaLessonDetailsScreen(
                              lesson: lesson,
                              childName: widget.childName,
                              childId: widget.childId,
                              parentId: widget.parentId, // Pass parentId
                            ),
                          ),
                        );
                      },
                child: Container(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Level Icon
                          Container(
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              lesson.icon,
                              style: TextStyle(fontSize: 24.sp),
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Level ${lesson.id}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    if (isCompleted)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8.w,
                                          vertical: 2.h,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            8.r,
                                          ),
                                        ),
                                        child: Text(
                                          '✓ Completed',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.sp,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    if (isLocked)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8.w,
                                          vertical: 2.h,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            8.r,
                                          ),
                                        ),
                                        child: Text(
                                          '🔒 Locked',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.sp,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  lesson.title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  lesson.tagline,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Action Icon
                          Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Icon(
                              isLocked
                                  ? Icons.lock_rounded
                                  : isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20.sp,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingElements() {
    return SizedBox(
      height: 100.h,
      child: Stack(
        children: [
          // Floating coins
          Positioned(
            top: 20.h,
            right: 20.w,
            child: AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _floatingAnimation.value),
                  child: Text('🪙', style: TextStyle(fontSize: 32.sp)),
                );
              },
            ),
          ),
          Positioned(
            top: 40.h,
            left: 30.w,
            child: AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -_floatingAnimation.value),
                  child: Text('⭐', style: TextStyle(fontSize: 24.sp)),
                );
              },
            ),
          ),
          Positioned(
            top: 60.h,
            right: 60.w,
            child: AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _floatingAnimation.value * 0.5),
                  child: Text('💎', style: TextStyle(fontSize: 20.sp)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LessonLevel {
  final int id;
  final String title;
  final String tagline;
  final String icon;
  final List<Color> gradient;
  final bool isUnlocked;
  final bool isCompleted;

  LessonLevel({
    required this.id,
    required this.title,
    required this.tagline,
    required this.icon,
    required this.gradient,
    required this.isUnlocked,
    required this.isCompleted,
  });
}
