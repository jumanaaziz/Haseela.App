import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ use Auth UID
import '../../models/task.dart';
import '../../models/child_options.dart';

class AssignTaskScreen extends StatefulWidget {
  const AssignTaskScreen({super.key});

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  void _showError(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFFF6A5D),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
  }

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _allowanceController = TextEditingController();

  DateTime? _toDate;
  String? _selectedChildId;
  TaskPriority? _priority;
  bool _isChallengeTask = false;

  List<ChildOption> _children = [];
  bool _loadingChildren = false;

  // Validation state
  String? _formError;
  String? _nameError;
  String? _childError;
  String? _dateError;
  String? _priorityError;
  String? _allowanceError;

  // ✅ current parent UID
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _fetchChildren();
  }

  Future<void> _fetchChildren() async {
    setState(() => _loadingChildren = true);
    try {
      print('=== FETCHING CHILDREN FOR ASSIGN TASK ===');
      print('Parent UID: $_uid');

      final snap = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid) // ✅ dynamic parent
          .collection("Children")
          .get();

      print('Children snapshot size: ${snap.docs.length}');

      final allChildren = snap.docs
          .map((doc) {
            final data = doc.data();
            print(
              'Child doc ${doc.id}: firstName=${data['firstName']}, data=$data',
            );
            try {
              return ChildOption.fromFirestore(doc.id, data);
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
      print('Children names: ${allChildren.map((c) => c.firstName).toList()}');

      setState(() {
        _children = allChildren;
      });
    } catch (e, stackTrace) {
      print('❌ Error loading children: $e');
      print('Stack trace: $stackTrace');
      _showError("Error loading children: $e");
    } finally {
      if (mounted) setState(() => _loadingChildren = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _allowanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Container(
          margin: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: const Color(0xFF64748B),
              size: 20.sp,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Assign Task',
          style: TextStyle(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
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
        child: _loadingChildren
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(20.w),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
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
                      'Loading children...',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Form Error Display
                    if (_formError != null)
                      Container(
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: 24.h),
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFEF2F2),
                              const Color(0xFFFFF5F5),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: const Color(0xFFFECACA),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8.w),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: const Color(0xFFDC2626),
                                size: 20.sp,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Text(
                                _formError!,
                                style: TextStyle(
                                  color: const Color(0xFFDC2626),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Task Name Section
                    _FormSection(
                      title: 'Task Name',
                      icon: Icons.task_alt_rounded,
                      child: _buildTextField(
                        controller: _nameController,
                        hintText: 'Enter task name',
                        errorText: _nameError,
                        maxLength: 80,
                        inputFormatters: [LengthLimitingTextInputFormatter(80)],
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Child Selection Section (only show if not a challenge task)
                    if (!_isChallengeTask) ...[
                      _FormSection(
                        title: 'Assign To',
                        icon: Icons.person_add_rounded,
                        child: _ChildSelector(
                          children: _children,
                          selectedChildId: _selectedChildId,
                          onSelected: (id) =>
                              setState(() => _selectedChildId = id),
                        ),
                        errorText: _childError,
                      ),
                      SizedBox(height: 24.h),
                    ],

                    // Due Date Section
                    _FormSection(
                      title: 'Due Date',
                      icon: Icons.calendar_today_rounded,
                      errorText: _dateError,
                      child: _DateBox(
                        label: _toDate == null
                            ? 'Select due date'
                            : _formatDate(_toDate!),
                        iconColor: const Color.fromARGB(
                          0,
                          255,
                          255,
                          255,
                        ), // 👈 makes icon invisible
                        onTap: () async {
                          final picked = await _pickDate(
                            context,
                            initial: _toDate,
                          );
                          if (picked != null) setState(() => _toDate = picked);
                        },
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Priority Section
                    _FormSection(
                      title: 'Priority Level',
                      icon: Icons.flag_rounded,
                      child: Wrap(
                        spacing: 12.w,
                        runSpacing: 12.h,
                        children: TaskPriority.values.map((p) {
                          final selected = _priority == p;
                          final priorityColor = _getPriorityColor(p);
                          return Container(
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? LinearGradient(
                                      colors: [
                                        priorityColor.withOpacity(0.1),
                                        priorityColor.withOpacity(0.05),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: selected
                                    ? priorityColor
                                    : const Color(0xFFE2E8F0),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setState(() => _priority = p),
                                borderRadius: BorderRadius.circular(12.r),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16.w,
                                    vertical: 12.h,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(6.w),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? priorityColor.withOpacity(0.2)
                                              : const Color(0xFFF1F5F9),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.circle,
                                          color: selected
                                              ? priorityColor
                                              : const Color(0xFF94A3B8),
                                          size: 12.sp,
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        _priorityText(p),
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w600,
                                          color: selected
                                              ? priorityColor
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      errorText: _priorityError,
                    ),

                    SizedBox(height: 24.h),

                    // Allowance Section
                    _FormSection(
                      title: 'Allowance',
                      icon: Icons.monetization_on_rounded,
                      child: _buildTextField(
                        controller: _allowanceController,
                        hintText: '0.00',
                        keyboardType: TextInputType.number,
                        prefix: const _RiyalSuffix(),
                        errorText: _allowanceError,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                          PositiveNumberFormatter(),
                        ],
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Challenge Task Section
                    _FormSection(
                      title: 'Challenge Task',
                      icon: Icons.emoji_events_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: _isChallengeTask
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFFE2E8F0),
                                width: _isChallengeTask ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setState(
                                  () => _isChallengeTask = !_isChallengeTask,
                                ),
                                borderRadius: BorderRadius.circular(12.r),
                                child: Container(
                                  padding: EdgeInsets.all(16.w),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24.w,
                                        height: 24.w,
                                        decoration: BoxDecoration(
                                          color: _isChallengeTask
                                              ? const Color(0xFF7C3AED)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            6.r,
                                          ),
                                          border: Border.all(
                                            color: _isChallengeTask
                                                ? const Color(0xFF7C3AED)
                                                : const Color(0xFF94A3B8),
                                            width: 2,
                                          ),
                                        ),
                                        child: _isChallengeTask
                                            ? Icon(
                                                Icons.check_rounded,
                                                color: Colors.white,
                                                size: 16.sp,
                                              )
                                            : null,
                                      ),
                                      SizedBox(width: 12.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Make it a challenge task',
                                              style: TextStyle(
                                                fontSize: 15.sp,
                                                fontWeight: FontWeight.w600,
                                                color: _isChallengeTask
                                                    ? const Color(0xFF7C3AED)
                                                    : const Color(0xFF1E293B),
                                              ),
                                            ),
                                            SizedBox(height: 4.h),
                                            Text(
                                              'All children can participate. Leaderboard shows who completed it first.',
                                              style: TextStyle(
                                                fontSize: 12.sp,
                                                color: const Color(0xFF64748B),
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 32.h),

                    // Submit Button
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF7C3AED),
                            const Color(0xFF8B5CF6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16.r),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED).withOpacity(0.3),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _handleSubmit,
                          borderRadius: BorderRadius.circular(16.r),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 18.h),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_task_rounded,
                                  color: Colors.white,
                                  size: 20.sp,
                                ),
                                SizedBox(width: 12.w),
                                Text(
                                  'Create Task',
                                  style: TextStyle(
                                    fontSize: 16.sp,
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
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    // Reset validation errors
    setState(() {
      _formError = null;
      _nameError = null;
      _childError = null;
      _dateError = null;
      _priorityError = null;
      _allowanceError = null;
    });

    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      _nameError = 'Please enter a task name';
    } else if (trimmedName.length < 3) {
      _nameError = 'Task name must be at least 3 characters';
    }
    // Only require child selection if it's NOT a challenge task
    if (!_isChallengeTask && _selectedChildId == null) {
      _childError = 'Please select a child';
    }
    if (_toDate == null) _dateError = 'Please select an end date';
    if (_priority == null) _priorityError = 'Please choose a priority';

    final allowanceText = _allowanceController.text.trim();
    double? allowance;
    if (allowanceText.isEmpty) {
      _allowanceError = 'Please enter an allowance amount';
    } else {
      allowance = double.tryParse(allowanceText);
      if (allowance == null) {
        _allowanceError = 'Allowance must be a valid number';
      }
      if (allowance != null && allowance > 9999) {
        _allowanceError = 'Allowance cannot exceed 9999 SAR';
      }
    }

    final hasErrors = [
      _nameError,
      _childError,
      _dateError,
      _priorityError,
      _allowanceError,
    ].any((e) => e != null);

    if (hasErrors) {
      setState(() {
        _formError = 'Please fix the highlighted fields and try again.';
      });
      return;
    }

    try {
      final parentRef = FirebaseFirestore.instance
          .collection('Parents')
          .doc(_uid); // ✅

      final taskData = {
        'taskName': trimmedName,
        'allowance': allowance,
        'status': 'new', // matches your TaskStatus.newTask
        'priority': _priority.toString().split('.').last.toLowerCase(),
        'dueDate': _toDate != null ? Timestamp.fromDate(_toDate!) : null, // ✅
        'createdAt': FieldValue.serverTimestamp(),
        'assignedBy': parentRef, // DocumentReference
        'completedImagePath': null,
        'completedDate': null, // ✅ Add this line
        'isChallenge': _isChallengeTask, // Challenge task flag
        // Initialize as null, will be updated when child uploads image
      };

      if (_isChallengeTask) {
        // If it's a challenge task, assign it to ALL children
        final childrenSnapshot = await parentRef.collection('Children').get();

        if (childrenSnapshot.docs.isEmpty) {
          _showError("No children found. Please add a child first.");
          return;
        }

        final batch = FirebaseFirestore.instance.batch();

        for (var childDoc in childrenSnapshot.docs) {
          final taskDoc = parentRef
              .collection('Children')
              .doc(childDoc.id)
              .collection('Tasks')
              .doc();

          batch.set(taskDoc, taskData);
        }

        await batch.commit();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Challenge task assigned to ${childrenSnapshot.docs.length} children ✅',
            ),
          ),
        );
      } else {
        // Regular task: assign to selected child only
        final taskDoc = parentRef
            .collection('Children')
            .doc(_selectedChildId!)
            .collection('Tasks')
            .doc();

        await taskDoc.set(taskData);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task assigned successfully ✅')),
        );
      }

      // Your TaskManagementScreen listens via StreamBuilder, so no need to return Task
      Navigator.pop(context);
    } catch (e) {
      _showError("Error assigning task: $e");
    }
  }

  Future<DateTime?> _pickDate(BuildContext context, {DateTime? initial}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.9)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF7C3AED),
                    onPrimary: Colors.white,
                    onSurface: Color(0xFF111827),
                  ),
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                    ),
                  ),
                  dialogTheme: DialogThemeData(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                child: child!,
              ),
            ),
          ),
        );
      },
    );
    return picked;
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  String _priorityText(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.normal:
        return 'Normal';
      case TaskPriority.high:
        return 'High';
    }
  }

  Color _getPriorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return const Color(0xFF10B981); // Green
      case TaskPriority.normal:
        return const Color(0xFFF59E0B); // Yellow
      case TaskPriority.high:
        return const Color(0xFFEF4444); // Red
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    Widget? prefix,
    String? errorText,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 14.sp,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: prefix,
          filled: true,
          fillColor: Colors.white,
          errorText: errorText,
          errorStyle: TextStyle(
            fontSize: 12.sp,
            color: const Color(0xFFDC2626),
            fontWeight: FontWeight.w500,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16.w,
            vertical: 16.h,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFFDC2626)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
          ),
        ),
      ),
    );
  }
}

/* ---------- Child Selector ---------- */

class _ChildSelector extends StatelessWidget {
  final List<ChildOption> children;
  final String? selectedChildId;
  final ValueChanged<String> onSelected;

  const _ChildSelector({
    required this.children,
    required this.selectedChildId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.map((c) {
        final isSelected = c.id == selectedChildId;
        return Container(
          margin: EdgeInsets.only(bottom: 8.h),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      const Color(0xFF7C3AED).withOpacity(0.1),
                      const Color(0xFF7C3AED).withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelected(c.id),
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                padding: EdgeInsets.all(16.w),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFFE2E8F0),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 24.r,
                        backgroundColor: Colors.white,
                        backgroundImage:
                            (c.avatar != null && c.avatar!.isNotEmpty)
                            ? NetworkImage(c.avatar!)
                            : null,
                        child: (c.avatar == null || c.avatar!.isEmpty)
                            ? Text(
                                c.firstName[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7C3AED),
                                ),
                              )
                            : null,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Text(
                        c.firstName,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16.sp,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final String? errorText;

  const _FormSection({
    required this.title,
    required this.icon,
    required this.child,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, color: const Color(0xFF7C3AED), size: 18.sp),
            ),
            SizedBox(width: 12.w),
            Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        child,
        if (errorText != null) ...[
          SizedBox(height: 8.h),
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: const Color(0xFFDC2626),
                size: 16.sp,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  errorText!,
                  style: TextStyle(
                    color: const Color(0xFFDC2626),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _DateBox({
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    color: iconColor,
                    size: 18.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                      color: label == 'Select due date'
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RiyalSuffix extends StatelessWidget {
  const _RiyalSuffix();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Image.asset(
        'assets/icons/riyal.png',
        width: 16.w,
        height: 16.w,
        fit: BoxFit.contain,
        color: const Color(0xFF7C3AED),
      ),
    );
  }
}

class PositiveNumberFormatter extends TextInputFormatter {
  static const double maxValue = 9999;
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final value = double.tryParse(newValue.text);
    if (value == null || value < 0 || value >= maxValue) {
      return oldValue;
    }
    return newValue;
  }
}
