import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../models/task.dart';
import 'assign_task_screen.dart';
import '../../models/child_options.dart';
import '../../widgets/task_card.dart';
import '../../widgets/custom_bottom_nav.dart';
import 'parent_profile_screen.dart';
import 'parent_leaderboard_screen.dart';
import 'parent_wishlist_screen.dart';

class TaskManagementScreen extends StatefulWidget {
  const TaskManagementScreen({super.key});

  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen> {
  // ✅ Always use the signed-in parent's UID
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  String selectedUserId = '';
  List<ChildOption> _children = [];
  Map<String, List<Task>> _currentGroupedTasks = {};
  StreamSubscription<QuerySnapshot>? _childrenSubscription;

  @override
  void initState() {
    super.initState();
    _setupChildrenListener();
  }

  @override
  void dispose() {
    _childrenSubscription?.cancel();
    super.dispose();
  }

  /// ✅ Set up real-time listener for children
  void _setupChildrenListener() {
    print('=== SETTING UP REAL-TIME CHILDREN LISTENER FOR TASK PAGE ===');
    print('Parent UID: $_uid');

    _childrenSubscription?.cancel(); // Cancel existing subscription

    _childrenSubscription = FirebaseFirestore.instance
        .collection("Parents")
        .doc(_uid)
        .collection("Children")
        .snapshots(includeMetadataChanges: true)
        .listen(
          (QuerySnapshot snapshot) {
            print('=== REAL-TIME UPDATE RECEIVED IN TASK PAGE ===');
            print('Snapshot size: ${snapshot.docs.length}');

            final allChildren = snapshot.docs
                .map((doc) {
                  final childData = doc.data() as Map<String, dynamic>?;
                  print('Child doc ${doc.id}: data=$childData');
                  if (childData == null) {
                    print('⚠️ Child data is null for ${doc.id}');
                    return null;
                  }
                  try {
                    return ChildOption.fromFirestore(doc.id, childData);
                  } catch (e) {
                    print('❌ Error creating ChildOption from ${doc.id}: $e');
                    return null;
                  }
                })
                .where((c) => c != null)
                .cast<ChildOption>()
                .where((c) => c.firstName.trim().isNotEmpty)
                .toList();

            print('Filtered to ${allChildren.length} children');
            print(
              'Children names: ${allChildren.map((c) => c.firstName).toList()}',
            );

            if (mounted) {
              setState(() {
                _children = allChildren;

                // If no child is selected or selected child no longer exists, select first one
                if (_children.isNotEmpty) {
                  if (selectedUserId.isEmpty ||
                      !_children.any((c) => c.id == selectedUserId)) {
                    selectedUserId = _children.first.id;
                    print(
                      'Selected child: ${_children.first.firstName} (${selectedUserId})',
                    );
                  }
                } else {
                  selectedUserId = '';
                  print('⚠️ No children found');
                }
              });
              print('=== CHILDREN LIST UPDATED IN TASK PAGE ===');
              print('New children count: ${_children.length}');
            } else {
              print('Widget not mounted, skipping setState');
            }
          },
          onError: (error, stackTrace) {
            print('❌ Error in children listener (Task Page): $error');
            print('Stack trace: $stackTrace');
            if (mounted) {
              _toast(
                'Error loading children: $error',
                ToastificationType.error,
              );
              // Try to re-setup listener after error
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _setupChildrenListener();
                }
              });
            }
          },
        );

    print('✅ Children listener set up successfully for task page');
  }

  /// ✅ Delete task (by UID + selected child)
  Future<void> _deleteTask(String taskId) async {
    if (selectedUserId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection("Parents")
        .doc(_uid)
        .collection("Children")
        .doc(selectedUserId)
        .collection("Tasks")
        .doc(taskId)
        .delete();
  }

  /// ✅ Confirm delete dialog
  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete task?', style: TextStyle(fontSize: 16.sp)),
          content: Text(
            'Are you sure you want to delete this task?',
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete', style: TextStyle(fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _toast(String msg, ToastificationType type) {
    toastification.show(
      context: context,
      type: type,
      style: ToastificationStyle.fillColored,
      title: Text(msg),
      autoCloseDuration: const Duration(seconds: 2),
    );
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
        // already on Tasks
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentLeaderboardScreen()),
        );
        break;
    }
  }

  /// ✅ Show edit task bottom sheet
  void _showEditTaskBottomSheet(Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditTaskBottomSheet(task: task),
    );
  }

  /// ✅ Show task details bottom sheet
  _showTaskDetailsBottomSheet(Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailsBottomSheet(
        task: task,
        childId: selectedUserId, // ✅ pass it here
      ),
    );
  }

  /// ✅ Group tasks by status in the specified order
  Map<String, List<Task>> _groupTasksByStatus(List<Task> tasks) {
    final Map<String, List<Task>> grouped = {
      'Waiting Approval': [],
      'To-Do': [],
      'Completed': [],
      'Rejected': [],
    };

    for (final task in tasks) {
      switch (task.taskStatus) {
        case TaskStatus.pending:
          grouped['Waiting Approval']!.add(task);
          break;
        case TaskStatus.newTask:
          grouped['To-Do']!.add(task);
          break;
        case TaskStatus.done:
          grouped['Completed']!.add(task);
          break;
        case TaskStatus.rejected:
          grouped['Rejected']!.add(task);
          break;
      }
    }

    return grouped;
  }

  /// ✅ Get total count of items including headers
  int _getTotalGroupedItemCount(Map<String, List<Task>> groupedTasks) {
    int count = 0;
    for (final entry in groupedTasks.entries) {
      if (entry.value.isNotEmpty) {
        count += 1; // Header
        count += entry.value.length; // Tasks
      }
    }
    return count;
  }

  /// ✅ Get item at specific index (header or task)
  dynamic _getGroupedItemAtIndex(
    Map<String, List<Task>> groupedTasks,
    int index,
  ) {
    int currentIndex = 0;

    for (final entry in groupedTasks.entries) {
      if (entry.value.isNotEmpty) {
        // Add header
        if (currentIndex == index) {
          return entry.key;
        }
        currentIndex++;

        // Add tasks
        for (final task in entry.value) {
          if (currentIndex == index) {
            return task;
          }
          currentIndex++;
        }
      }
    }

    return null;
  }

  /// ✅ Build section header widget
  Widget _buildSectionHeader(String status) {
    return Container(
      margin: EdgeInsets.only(top: 24.h, bottom: 16.h),
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              _getStatusIcon(status),
              size: 16.sp,
              color: const Color(0xFF7C3AED),
            ),
          ),
          SizedBox(width: 12.w),
          Text(
            status,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              '${_getTaskCountForStatus(status)}',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Waiting Approval':
        return Icons.hourglass_empty_rounded;
      case 'To-Do':
        return Icons.assignment_rounded;
      case 'Completed':
        return Icons.check_circle_rounded;
      case 'Rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.task_rounded;
    }
  }

  int _getTaskCountForStatus(String status) {
    // Make sure data exists
    if (_currentGroupedTasks.isEmpty) return 0;

    // Match status key safely
    if (_currentGroupedTasks.containsKey(status)) {
      return _currentGroupedTasks[status]?.length ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 1,
        onTap: (i) => _onNavTap(context, i),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: SafeArea(
          bottom: false,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                // App title - centered
                Expanded(
                  child: Center(
                    child: Text(
                      'Tasks',
                      style: TextStyle(
                        color: const Color(0xFF1E293B),
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                // Add Task Button
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF7C3AED),
                        const Color(0xFF8B5CF6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AssignTaskScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12.r),
                      child: Container(
                        padding: EdgeInsets.all(12.w),
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 20.sp,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
        child: Column(
          children: [
            // 👶 Child pills
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _children.map((child) {
                    final isSelected = child.id == selectedUserId;
                    return Container(
                      margin: EdgeInsets.only(right: 12.w),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() => selectedUserId = child.id);
                          },
                          borderRadius: BorderRadius.circular(16.r),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20.w,
                              vertical: 12.h,
                            ),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                      colors: [
                                        const Color(0xFF7C3AED),
                                        const Color(0xFF8B5CF6),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isSelected ? null : Colors.white,
                              borderRadius: BorderRadius.circular(16.r),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.transparent
                                    : const Color(0xFFE2E8F0),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? const Color(0xFF7C3AED).withOpacity(0.3)
                                      : Colors.black.withOpacity(0.05),
                                  blurRadius: isSelected ? 8 : 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              child.firstName,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 📋 Task list
            Expanded(
              child: selectedUserId.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(24.w),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20.r),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.person_search_rounded,
                              size: 48.sp,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            "Select a child to view tasks",
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            "Choose a child from the options above",
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("Parents")
                          .doc(_uid)
                          .collection("Children")
                          .doc(selectedUserId)
                          .collection("Tasks")
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(24.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20.r),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    color: const Color(0xFFEF4444),
                                    size: 48.sp,
                                  ),
                                ),
                                SizedBox(height: 16.h),
                                Text(
                                  'Error loading tasks',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  'Please try again later',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(24.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20.r),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      const Color(0xFF7C3AED),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 16.h),
                                Text(
                                  'Loading tasks...',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(24.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20.r),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.task_alt_rounded,
                                    size: 48.sp,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                                SizedBox(height: 16.h),
                                Text(
                                  'No tasks yet',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  'Create your first task to get started',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final allTasks = docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          // Handle assignedBy field - can be DocumentReference or String
                          DocumentReference assignedByRef;
                          if (data['assignedBy'] is DocumentReference) {
                            assignedByRef =
                                data['assignedBy'] as DocumentReference;
                          } else if (data['assignedBy'] is String) {
                            final assignedByPath = data['assignedBy'] as String;
                            if (assignedByPath.isNotEmpty &&
                                assignedByPath.contains('/')) {
                              try {
                                assignedByRef = FirebaseFirestore.instance.doc(
                                  assignedByPath,
                                );
                              } catch (_) {
                                assignedByRef = FirebaseFirestore.instance
                                    .collection('Parents')
                                    .doc(_uid);
                              }
                            } else {
                              assignedByRef = FirebaseFirestore.instance
                                  .collection('Parents')
                                  .doc(_uid);
                            }
                          } else {
                            assignedByRef = FirebaseFirestore.instance
                                .collection('Parents')
                                .doc(_uid);
                          }

                          return Task(
                            id: doc.id,
                            taskName: data['taskName'] ?? '',
                            allowance: (data['allowance'] ?? 0).toDouble(),
                            status: Task.normalizeStatus(data['status']),
                            priority: data['priority'] ?? 'normal',
                            dueDate: data['dueDate'] != null
                                ? (data['dueDate'] as Timestamp).toDate()
                                : null,
                            createdAt: data['createdAt'] != null
                                ? (data['createdAt'] as Timestamp).toDate()
                                : DateTime.now(),
                            completedDate: data['completedDate'] != null
                                ? (data['completedDate'] as Timestamp).toDate()
                                : null,
                            assignedBy: assignedByRef,
                            completedImagePath: data['completedImagePath'],
                            isChallenge: data['isChallenge'] ?? false,
                          );
                        }).toList();

                        // Group tasks by status
                        _currentGroupedTasks = _groupTasksByStatus(allTasks);
                        final groupedTasks = _currentGroupedTasks;

                        return Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: 16.w),
                                itemCount: _getTotalGroupedItemCount(
                                  groupedTasks,
                                ),
                                itemBuilder: (context, index) {
                                  final item = _getGroupedItemAtIndex(
                                    groupedTasks,
                                    index,
                                  );

                                  if (item is String) {
                                    // This is a section header
                                    return _buildSectionHeader(item);
                                  } else if (item is Task) {
                                    // This is a task
                                    return Dismissible(
                                      key: Key(item.id),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        color: Colors.red,
                                        alignment: Alignment.centerRight,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20.w,
                                        ),
                                        child: Icon(
                                          Icons.delete,
                                          color: Colors.white,
                                          size: 20.sp,
                                        ),
                                      ),
                                      confirmDismiss: (_) async {
                                        return await _confirmDelete(context);
                                      },
                                      onDismissed: (_) async {
                                        await _deleteTask(item.id);
                                        if (context.mounted) {
                                          toastification.show(
                                            context: context,
                                            type: ToastificationType.success,
                                            style:
                                                ToastificationStyle.flatColored,
                                            title: Text(
                                              'Task deleted',
                                              style: TextStyle(fontSize: 14.sp),
                                            ),
                                            autoCloseDuration: const Duration(
                                              seconds: 2,
                                            ),
                                          );
                                        }
                                      },
                                      child: TaskCard(
                                        task: item,
                                        onTapArrow: () =>
                                            _showTaskDetailsBottomSheet(item),
                                        onEdit: () =>
                                            _showEditTaskBottomSheet(item),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(16.w),
                              margin: EdgeInsets.symmetric(horizontal: 20.w),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF7C3AED).withOpacity(0.05),
                                    const Color(0xFF8B5CF6).withOpacity(0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: const Color(
                                    0xFF7C3AED,
                                  ).withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8.w),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF7C3AED,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8.r),
                                    ),
                                    child: Icon(
                                      Icons.swipe_right_rounded,
                                      color: const Color(0xFF7C3AED),
                                      size: 16.sp,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      'Swipe left on any task to delete it',
                                      style: TextStyle(
                                        color: const Color(0xFF7C3AED),
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ Task Details Bottom Sheet Widget
class TaskDetailsBottomSheet extends StatefulWidget {
  final Task task;
  final String childId;

  const TaskDetailsBottomSheet({
    super.key,
    required this.task,
    required this.childId,
  });

  @override
  State<TaskDetailsBottomSheet> createState() => _TaskDetailsBottomSheetState();
}

class _TaskDetailsBottomSheetState extends State<TaskDetailsBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        final isSmallScreen = screenHeight < 700;
        final isVerySmallScreen = screenHeight < 600;

        return Container(
          height: isVerySmallScreen
              ? screenHeight * 0.85
              : isSmallScreen
              ? screenHeight * 0.75
              : screenHeight * 0.7,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(screenWidth * 0.05),
              topRight: Radius.circular(screenWidth * 0.05),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: screenHeight * 0.015),
                width: screenWidth * 0.1,
                height: screenHeight * 0.005,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(screenHeight * 0.0025),
                ),
              ),

              // Header
              Container(
                padding: EdgeInsets.all(screenWidth * 0.05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Task Details',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 18.sp : 20.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Text(
                      widget.task.taskName,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13.sp : 14.sp,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    if (widget.task.completedDate != null) ...[
                      SizedBox(height: screenHeight * 0.01),
                    ],
                  ],
                ),
              ),

              // Tab bar
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color.fromARGB(255, 144, 94, 228),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: const Color.fromARGB(255, 144, 94, 228),
                  labelStyle: TextStyle(
                    fontSize: isSmallScreen ? 13.sp : 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: isSmallScreen ? 12.sp : 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: 'Photo'),
                    Tab(text: 'Details'),
                  ],
                ),
              ),

              // Tab content - Scrollable
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Photo tab
                    SingleChildScrollView(
                      padding: EdgeInsets.all(screenWidth * 0.05),
                      child: _buildPhotoTab(),
                    ),
                    // Priority tab
                    SingleChildScrollView(
                      padding: EdgeInsets.all(screenWidth * 0.05),
                      child: _buildPriorityTab(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhotoTab() {
    return Column(
      children: [
        if (widget.task.completedImagePath != null &&
            widget.task.completedImagePath!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.25,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                MediaQuery.of(context).size.width * 0.03,
              ),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                MediaQuery.of(context).size.width * 0.03,
              ),
              child: Image.network(
                widget.task.completedImagePath!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[100],
                    child: Icon(
                      Icons.image_not_supported,
                      size: MediaQuery.of(context).size.width * 0.12,
                      color: Colors.grey[400],
                    ),
                  );
                },
              ),
            ),
          ),
        ] else ...[
          Container(
            height: MediaQuery.of(context).size.height * 0.25,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(
                MediaQuery.of(context).size.width * 0.03,
              ),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: MediaQuery.of(context).size.width * 0.15,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  Text(
                    'No photo were uploaded',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriorityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Approval/Reject buttons for pending tasks - Above Task Priority
        if (widget.task.taskStatus == TaskStatus.pending) ...[
          Container(
            padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                MediaQuery.of(context).size.width * 0.04,
              ),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Task Review',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red[400]!, Colors.red[600]!],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(
                            MediaQuery.of(context).size.width * 0.025,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _rejectTask(widget.task),
                            borderRadius: BorderRadius.circular(
                              MediaQuery.of(context).size.width * 0.025,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6.w),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 20.sp,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Text(
                                    'Reject',
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.04),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green[400]!, Colors.green[600]!],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(
                            MediaQuery.of(context).size.width * 0.025,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _approveTask(widget.task),
                            borderRadius: BorderRadius.circular(
                              MediaQuery.of(context).size.width * 0.025,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6.w),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: 20.sp,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Text(
                                    'Approve',
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                Text(
                  'Review the task completion and decide whether to approve or reject',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.025),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 400;
            return Text(
              'Task Priority',
              style: TextStyle(
                fontSize: isSmallScreen ? 16.sp : 18.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            );
          },
        ),
        SizedBox(height: 16.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width * 0.05,
            vertical: MediaQuery.of(context).size.height * 0.02,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _getPriorityColor(widget.task.priority).withOpacity(0.1),
                _getPriorityColor(widget.task.priority).withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(
              MediaQuery.of(context).size.width * 0.04,
            ),
            border: Border.all(
              color: _getPriorityColor(widget.task.priority).withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _getPriorityColor(widget.task.priority).withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth < 400;
              return Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 6.w : 8.w),
                    decoration: BoxDecoration(
                      color: _getPriorityColor(
                        widget.task.priority,
                      ).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getPriorityIcon(widget.task.priority),
                      color: _getPriorityColor(widget.task.priority),
                      size: isSmallScreen ? 16.sp : 20.sp,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 12.w : 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Priority Level',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10.sp : 12.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B7280),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          _getPriorityText(widget.task.priority),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14.sp : 16.sp,
                            fontWeight: FontWeight.w700,
                            color: _getPriorityColor(widget.task.priority),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: 20.h),
        LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 400;
            return Text(
              'Task Details',
              style: TextStyle(
                fontSize: isSmallScreen ? 16.sp : 18.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            );
          },
        ),
        SizedBox(height: 16.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.05),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(
              MediaQuery.of(context).size.width * 0.04,
            ),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: Column(
            children: [
              _buildDetailRow(
                'Due Date',
                _formatDate(widget.task.dueDate ?? DateTime.now()),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.015),
              _buildDetailRow('Created', _formatDate(widget.task.createdAt)),
              SizedBox(height: MediaQuery.of(context).size.height * 0.015),
              _buildDetailRow(
                'Allowance',
                '${widget.task.allowance.toStringAsFixed(0)} ﷼',
              ),
              if (widget.task.completedDate != null) ...[
                SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                _buildDetailRow(
                  'Completed',
                  _formatDate(widget.task.completedDate!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;
        final isVerySmallScreen = constraints.maxWidth < 300;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.015,
            horizontal: MediaQuery.of(context).size.width * 0.04,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(
              MediaQuery.of(context).size.width * 0.03,
            ),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: isVerySmallScreen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12.sp : 14.sp,
                        color: const Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13.sp : 14.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12.sp : 14.sp,
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.02),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13.sp : 14.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A1A),
                        ),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  // ✅ FIXED _approveTask METHOD
  Future<void> _approveTask(Task task) async {
    try {
      // Step 1️⃣ Confirm approval
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Approve Task'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to approve this task?'),
              SizedBox(height: 8),
              Text(
                'Task: ${task.taskName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Allowance: +${task.allowance.toStringAsFixed(0)} ﷼',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Approve'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Step 2️⃣ Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          title: Text('Approving Task...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Updating task status and wallet...'),
            ],
          ),
        ),
      );

      // Step 3️⃣ Firestore references
      final parentId = FirebaseAuth.instance.currentUser!.uid;
      final childRef = FirebaseFirestore.instance
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(widget.childId);

      print(
        '🔥 APPROVE DEBUG - ParentID: $parentId | ChildID: ${widget.childId}',
      );

      final taskRef = childRef.collection('Tasks').doc(task.id);
      final walletDocRef = childRef.collection('Wallet').doc('wallet001');

      // Step 4️⃣ Atomic transaction with FIXED totalBalance update
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final taskSnap = await tx.get(taskRef);
        final taskData = taskSnap.data() as Map<String, dynamic>?;

        // Avoid double credit if already done
        if (taskData != null &&
            (taskData['status']?.toString().toLowerCase() == 'done')) {
          print('⚠️ DEBUG: Task already approved, skipping balance update.');
          return;
        }

        // Get current wallet data
        final walletSnap = await tx.get(walletDocRef);
        final walletData = walletSnap.data() as Map<String, dynamic>?;

        if (walletData == null) {
          // Create new wallet if it doesn't exist
          print('✅ Creating new wallet with allowance: ${task.allowance}');
          tx.set(walletDocRef, {
            'totalBalance': task.allowance,
            'spendingBalance': 0.0,
            'savingBalance': 0.0,
            'savingGoal': 100.0,
            'userId': widget.childId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // ✅ FIX: Update existing wallet - directly calculate and set new totalBalance
          final currentTotal = (walletData['totalBalance'] ?? 0.0).toDouble();
          final newTotal = currentTotal + task.allowance;

          print(
            '✅ Updating wallet: Current=$currentTotal, Adding=${task.allowance}, New=$newTotal',
          );

          tx.update(walletDocRef, {
            'totalBalance':
                newTotal, // ✅ Direct value instead of FieldValue.increment
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Mark task as done
        // ✅ Preserve original completedDate (when child completed) instead of overwriting with approval time
        final updateData = <String, dynamic>{'status': 'done'};
        // Only set completedDate if it doesn't already exist (preserve child's completion time)
        if (taskData == null || taskData['completedDate'] == null) {
          updateData['completedDate'] = FieldValue.serverTimestamp();
        }
        // If completedDate already exists, we don't update it - it preserves the child's completion time
        tx.update(taskRef, updateData);

        print('✅ Transaction completed successfully');
      });

      // Step 5️⃣ Close dialogs
      if (Navigator.canPop(context)) Navigator.pop(context); // Close loading
      if (Navigator.canPop(context))
        Navigator.pop(context); // Close bottom sheet

      // Step 6️⃣ Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Task approved! +${task.allowance.toStringAsFixed(0)} ﷼ added to total wallet.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      print('✅ Task approval completed - Total Balance updated');
    } catch (e, stackTrace) {
      // Close loading dialog if open
      if (Navigator.canPop(context)) Navigator.pop(context);

      print('❌ Error approving task: $e');
      print('Stack trace: $stackTrace');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error approving task: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _rejectTask(Task task) async {
    try {
      // Show confirmation dialog
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.cancel, color: Colors.red),
                SizedBox(width: 8.w),
                Text('Reject Task'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to reject this task?',
                  style: TextStyle(fontSize: 16.sp),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Task: ${task.taskName}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'The child will not receive the allowance.',
                  style: TextStyle(color: Colors.red[600], fontSize: 14.sp),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text('Reject'),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Rejecting Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16.h),
                  Text('Updating task status...'),
                ],
              ),
            );
          },
        );

        // Update task status to rejected
        await FirebaseFirestore.instance
            .collection('Parents')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .collection('Children')
            .doc(widget.childId)
            .collection('Tasks')
            .doc(task.id)
            .update({'status': 'rejected'});

        // Close loading dialog
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Close task details dialog
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task rejected successfully'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error rejecting task: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
      case 'normal':
        return Colors.yellow;
      case 'low':
        return Colors.green;
      default:
        return Colors.yellow;
    }
  }

  IconData _getPriorityIcon(String priority) {
    return Icons.circle;
  }

  String _getPriorityText(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return 'High Priority';
      case 'medium':
        return 'Medium Priority';
      case 'low':
        return 'Low Priority';
      default:
        return 'Normal Priority';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// ✅ Edit Task Bottom Sheet Widget
class EditTaskBottomSheet extends StatefulWidget {
  final Task task;

  const EditTaskBottomSheet({super.key, required this.task});

  @override
  State<EditTaskBottomSheet> createState() => _EditTaskBottomSheetState();
}

class _EditTaskBottomSheetState extends State<EditTaskBottomSheet> {
  late TextEditingController _titleController;
  DateTime? _selectedDate;
  String? _selectedPriority;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.taskName);
    _selectedDate = widget.task.dueDate;
    _selectedPriority = widget.task.priority;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.r),
          topRight: Radius.circular(20.r),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              children: [
                Text(
                  'Edit Task',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 20.h),

                // Title field
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: const Color(0xFF3B82F6)),
                    ),
                  ),
                ),

                SizedBox(height: 16.h),

                // Due Date field
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.grey[600]),
                        SizedBox(width: 12.w),
                        Text(
                          _selectedDate != null
                              ? 'Due Date: ${_formatDate(_selectedDate!)}'
                              : 'Select Due Date',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: _selectedDate != null
                                ? const Color(0xFF1A1A1A)
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16.h),

                // Priority field
                DropdownButtonFormField<String>(
                  value: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Details',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(
                        color: const Color.fromARGB(255, 144, 94, 228),
                      ),
                    ),
                  ),
                  items: ['low', 'medium', 'high'].map((String priority) {
                    return DropdownMenuItem<String>(
                      value: priority,
                      child: Text(
                        priority.toUpperCase(),
                        style: TextStyle(fontSize: 16.sp),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedPriority = newValue;
                    });
                  },
                ),

                SizedBox(height: 24.h),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.grey[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(fontSize: 16.sp),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveTask,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            144,
                            94,
                            228,
                          ),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                        ),
                        child: Text('Save', style: TextStyle(fontSize: 16.sp)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _saveTask() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please enter a task title')));
      return;
    }

    try {
      // Update task in Firestore
      await FirebaseFirestore.instance
          .collection("Parents")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection("Children")
          .doc(widget.task.assignedBy.path.split('/').last)
          .collection("Tasks")
          .doc(widget.task.id)
          .update({
            'taskName': _titleController.text.trim(),
            'dueDate': _selectedDate != null
                ? Timestamp.fromDate(_selectedDate!)
                : null,
            'priority': _selectedPriority ?? 'medium',
          });

      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Task updated successfully')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating task: $e')));
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
