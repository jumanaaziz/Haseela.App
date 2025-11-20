import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:toastification/toastification.dart';
import '../../models/child_options.dart';
import '../../models/allowance_settings.dart';
import '../services/allowance_service.dart';

class SetUpWeeklyAllowanceScreen extends StatefulWidget {
  final List<ChildOption> children;

  const SetUpWeeklyAllowanceScreen({super.key, required this.children});

  String get parentId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User is not authenticated');
    }
    return user.uid;
  }

  @override
  State<SetUpWeeklyAllowanceScreen> createState() =>
      _SetUpWeeklyAllowanceScreenState();
}

class _SetUpWeeklyAllowanceScreenState
    extends State<SetUpWeeklyAllowanceScreen> {
  // Selected children
  final Set<String> _selectedChildIds = {};

  // Allowance settings for each child
  final Map<String, AllowanceSettings?> _allowanceSettings = {};
  bool _isLoading = true;

  // Days of the week
  final List<String> _daysOfWeek = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingAllowances();
  }

  @override
  void dispose() {
    _isSavingNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadExistingAllowances() async {
    setState(() => _isLoading = true);
    try {
      for (var child in widget.children) {
        final settings = await AllowanceService.getAllowanceSettings(
          widget.parentId,
          child.id,
        );
        _allowanceSettings[child.id] = settings;
      }
    } catch (e) {
      print('Error loading allowances: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleChildSelection(String childId) {
    setState(() {
      if (_selectedChildIds.contains(childId)) {
        _selectedChildIds.remove(childId);
      } else {
        _selectedChildIds.add(childId);
      }
    });
  }

  final ValueNotifier<bool> _isSavingNotifier = ValueNotifier<bool>(false);

  Future<void> _saveAllowanceSettings(
    String amount,
    String day,
    bool isEnabled,
  ) async {
    if (_selectedChildIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one child',
            style: TextStyle(fontSize: 14.sp),
          ),
          backgroundColor: Colors.grey[700],
        ),
      );
      return;
    }

    if (amount.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter an allowance amount',
            style: TextStyle(fontSize: 14.sp),
          ),
          backgroundColor: Colors.grey[700],
        ),
      );
      return;
    }

    final weeklyAmount = double.tryParse(amount.trim());
    if (weeklyAmount == null || weeklyAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a valid amount',
            style: TextStyle(fontSize: 14.sp),
          ),
          backgroundColor: Colors.grey[700],
        ),
      );
      return;
    }

    _isSavingNotifier.value = true;

    try {
      // Create allowance settings
      final settings = AllowanceSettings(
        weeklyAmount: weeklyAmount,
        dayOfWeek: day,
        isEnabled: isEnabled,
      );

      // Save for each selected child (using merge for updates)
      for (var childId in _selectedChildIds) {
        final existing = _allowanceSettings[childId];
        final isEdit = existing != null && existing.isEnabled;

        await AllowanceService.saveAllowanceSettings(
          widget.parentId,
          childId,
          settings,
          merge: isEdit, // Use merge when editing
        );

        // Process immediate allowance if today matches (only for new settings or when enabled)
        if (isEnabled) {
          await AllowanceService.processImmediateAllowance(
            widget.parentId,
            childId,
            settings,
          );
        }
      }

      // Update local state
      setState(() {
        for (var childId in _selectedChildIds) {
          _allowanceSettings[childId] = settings;
        }
      });
      _isSavingNotifier.value = false;

      // Close bottom sheet and show success message
      if (mounted) {
        Navigator.of(context).pop(); // Close bottom sheet

        // Show success message
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: Text(
            'Weekly allowance saved successfully.',
            style: TextStyle(fontSize: 14.sp),
          ),
          autoCloseDuration: const Duration(seconds: 3),
        );

        // DO NOT navigate away - stay on the screen
      }
    } catch (e) {
      _isSavingNotifier.value = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving allowance: $e',
              style: TextStyle(fontSize: 14.sp),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAllowanceSettingsSheet() {
    if (_selectedChildIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one child',
            style: TextStyle(fontSize: 14.sp),
          ),
          backgroundColor: Colors.grey[700],
        ),
      );
      return;
    }

    // Check if any selected child has existing allowance
    bool hasExistingAllowance = false;
    AllowanceSettings? existingSettings;
    for (var childId in _selectedChildIds) {
      final settings = _allowanceSettings[childId];
      if (settings != null && settings.isEnabled) {
        hasExistingAllowance = true;
        existingSettings = settings;
        break; // Use first existing settings for pre-fill
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => ValueListenableBuilder<bool>(
          valueListenable: _isSavingNotifier,
          builder: (context, isSaving, _) => _AllowanceSettingsSheet(
            selectedChildIds: _selectedChildIds,
            children: widget.children,
            daysOfWeek: _daysOfWeek,
            existingSettings: existingSettings,
            isEditMode: hasExistingAllowance,
            isSaving: isSaving,
            onSave: (amount, day, isEnabled) async {
              await _saveAllowanceSettings(amount, day, isEnabled);
            },
            onDeleteChild: (childId) {
              setState(() {
                _selectedChildIds.remove(childId);
              });
              setModalState(() {}); // Update bottom sheet UI
              // Close bottom sheet if no children selected
              if (_selectedChildIds.isEmpty) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Please select at least one child',
                      style: TextStyle(fontSize: 14.sp),
                    ),
                    backgroundColor: Colors.grey[700],
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: const Color(0xFF1C1243),
            size: 20.sp,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Weekly Allowance',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1C1243),
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Simple Section Header
          Padding(
            padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Children',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1243),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Choose one or more children to set up weekly allowance',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),

          // Children List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFFFF8A00),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    itemCount: widget.children.length,
                    itemBuilder: (context, index) {
                      final child = widget.children[index];
                      final isSelected = _selectedChildIds.contains(child.id);
                      final allowance = _allowanceSettings[child.id];
                      final hasExistingAllowance =
                          allowance != null && allowance.isEnabled;

                      return _ChildCard(
                        child: child,
                        isSelected: isSelected,
                        allowance: allowance,
                        hasExistingAllowance: hasExistingAllowance,
                        onToggleSelection: () =>
                            _toggleChildSelection(child.id),
                      );
                    },
                  ),
          ),

          // Continue Button
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _showAllowanceSettingsSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: Text(
                'Continue',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple Child Card Widget
class _ChildCard extends StatelessWidget {
  final ChildOption child;
  final bool isSelected;
  final AllowanceSettings? allowance;
  final bool hasExistingAllowance;
  final VoidCallback onToggleSelection;

  const _ChildCard({
    required this.child,
    required this.isSelected,
    required this.allowance,
    required this.hasExistingAllowance,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isSelected ? const Color(0xFFFF8A00) : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          GestureDetector(
            onTap: onToggleSelection,
            child: Container(
              width: 24.w,
              height: 24.w,
              margin: EdgeInsets.only(top: 2.h),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFF8A00)
                      : const Color(0xFFCBD5E1),
                  width: 2,
                ),
                color: isSelected
                    ? const Color(0xFFFF8A00)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(Icons.check_rounded, size: 16.sp, color: Colors.white)
                  : null,
            ),
          ),
          SizedBox(width: 16.w),
          // Avatar
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF7F9FC),
            ),
            child: child.avatar != null && child.avatar!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      child.avatar!,
                      width: 56.w,
                      height: 56.w,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            child.initial,
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Center(
                    child: Text(
                      child.initial,
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
          ),
          SizedBox(width: 16.w),
          // Child Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  child.fullName,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1243),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (hasExistingAllowance && allowance != null) ...[
                  SizedBox(height: 6.h),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${allowance!.weeklyAmount.toStringAsFixed(0)} SAR every ${allowance!.dayOfWeek}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      // Status label
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: allowance!.isEnabled
                              ? const Color(0xFF10B981).withOpacity(0.1)
                              : const Color(0xFF64748B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          allowance!.isEnabled ? 'Active' : 'Paused',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: allowance!.isEnabled
                                ? const Color(0xFF10B981)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Allowance Settings Bottom Sheet
class _AllowanceSettingsSheet extends StatefulWidget {
  final Set<String> selectedChildIds;
  final List<ChildOption> children;
  final List<String> daysOfWeek;
  final AllowanceSettings? existingSettings;
  final bool isEditMode;
  final bool isSaving;
  final Function(String amount, String day, bool isEnabled) onSave;
  final Function(String childId) onDeleteChild;

  const _AllowanceSettingsSheet({
    required this.selectedChildIds,
    required this.children,
    required this.daysOfWeek,
    this.existingSettings,
    this.isEditMode = false,
    required this.isSaving,
    required this.onSave,
    required this.onDeleteChild,
  });

  @override
  State<_AllowanceSettingsSheet> createState() =>
      _AllowanceSettingsSheetState();
}

class _AllowanceSettingsSheetState extends State<_AllowanceSettingsSheet> {
  final TextEditingController _amountController = TextEditingController();
  String _selectedDay = 'Sunday';
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill fields if editing
    if (widget.existingSettings != null) {
      _amountController.text = widget.existingSettings!.weeklyAmount
          .toStringAsFixed(0);
      _selectedDay = widget.existingSettings!.dayOfWeek;
      _isEnabled = widget.existingSettings!.isEnabled;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (widget.isSaving) return; // Prevent multiple saves

    if (_amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter an allowance amount',
            style: TextStyle(fontSize: 14.sp),
          ),
          backgroundColor: Colors.grey[700],
        ),
      );
      return;
    }

    await widget.onSave(
      _amountController.text.trim(),
      _selectedDay,
      _isEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedChildren = widget.children
        .where((c) => widget.selectedChildIds.contains(c.id))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(24.r),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 12.h, bottom: 8.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),

            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allowance Settings',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1C1243),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'For ${selectedChildren.length} ${selectedChildren.length == 1 ? 'child' : 'children'}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),

            // Selected Children List with Delete Options
            if (selectedChildren.length > 1)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Children',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1C1243),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    ...selectedChildren.map((child) {
                      return Container(
                        margin: EdgeInsets.only(bottom: 8.h),
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F9FC),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 40.w,
                              height: 40.w,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE2E8F0),
                              ),
                              child:
                                  child.avatar != null &&
                                      child.avatar!.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        child.avatar!,
                                        width: 40.w,
                                        height: 40.w,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Center(
                                                child: Text(
                                                  child.initial,
                                                  style: TextStyle(
                                                    fontSize: 16.sp,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(
                                                      0xFF64748B,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        child.initial,
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                            ),
                            SizedBox(width: 12.w),
                            // Child Name
                            Expanded(
                              child: Text(
                                child.fullName,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF1C1243),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            // Remove Button
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: Colors.grey[500],
                                size: 18.sp,
                              ),
                              onPressed: widget.isSaving
                                  ? null
                                  : () {
                                      widget.onDeleteChild(child.id);
                                    },
                              tooltip: 'Remove child',
                              constraints: BoxConstraints(
                                minWidth: 36.w,
                                minHeight: 36.h,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    SizedBox(height: 24.h),
                  ],
                ),
              )
            else if (selectedChildren.length == 1)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Container(
                  margin: EdgeInsets.only(bottom: 24.h),
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE2E8F0),
                        ),
                        child:
                            selectedChildren[0].avatar != null &&
                                selectedChildren[0].avatar!.isNotEmpty
                            ? ClipOval(
                                child: Image.network(
                                  selectedChildren[0].avatar!,
                                  width: 40.w,
                                  height: 40.w,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Text(
                                        selectedChildren[0].initial,
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Center(
                                child: Text(
                                  selectedChildren[0].initial,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                      ),
                      SizedBox(width: 12.w),
                      // Child Name
                      Expanded(
                        child: Text(
                          selectedChildren[0].fullName,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1C1243),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      // Remove Button
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.grey[500],
                          size: 18.sp,
                        ),
                        onPressed: widget.isSaving
                            ? null
                            : () {
                                widget.onDeleteChild(selectedChildren[0].id);
                              },
                        tooltip: 'Remove child',
                        constraints: BoxConstraints(
                          minWidth: 36.w,
                          minHeight: 36.h,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),

            // Settings Form
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Amount Input
                  Text(
                    'Amount',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1C1243),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    enabled: !widget.isSaving,
                    decoration: InputDecoration(
                      hintText: 'Enter weekly amount',
                      suffixText: 'SAR',
                      suffixStyle: TextStyle(
                        fontSize: 14.sp,
                        color: const Color(0xFF64748B),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(
                          color: const Color(0xFFFF8A00),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7F9FC),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 16.h,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1C1243),
                    ),
                  ),
                  SizedBox(height: 24.h),

                  // Day Dropdown
                  Text(
                    'Day of Week',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1C1243),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<String>(
                    value: _selectedDay,
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.calendar_today_rounded,
                        color: const Color(0xFF64748B),
                        size: 20.sp,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(
                          color: const Color(0xFFFF8A00),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7F9FC),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 16.h,
                      ),
                    ),
                    items: widget.daysOfWeek.map((day) {
                      return DropdownMenuItem(
                        value: day,
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1C1243),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: widget.isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _selectedDay = value;
                              });
                            }
                          },
                  ),
                  SizedBox(height: 24.h),

                  // Enable/Disable Toggle
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Enable Weekly Allowance',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1C1243),
                          ),
                        ),
                      ),
                      Switch(
                        value: _isEnabled,
                        onChanged: widget.isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _isEnabled = value;
                                });
                              },
                        activeColor: const Color(0xFFFF8A00),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  // Description text
                  Padding(
                    padding: EdgeInsets.only(left: 4.w),
                    child: Text(
                      _isEnabled
                          ? 'When enabled, the weekly allowance will be automatically sent to your child every week on the selected day.'
                          : 'When disabled, the weekly allowance is paused. No automatic payments will be sent, even if an amount and day are saved.',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  SizedBox(height: 32.h),
                ],
              ),
            ),

            // Save/Update Button with Gradient and Loading
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isSaving ? null : _handleSave,
                  borderRadius: BorderRadius.circular(12.r),
                  child: Opacity(
                    opacity: widget.isSaving ? 0.7 : 1.0,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF8A00), // Primary orange
                            const Color(0xFFFF6A5D), // Coral red
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8A00).withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: widget.isSaving
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20.w,
                                  height: 20.h,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Text(
                                  'Saving...',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              widget.isEditMode
                                  ? 'Update Allowance'
                                  : 'Save Allowance',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
