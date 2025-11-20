import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:toastification/toastification.dart';
import '../../models/parent_profile.dart';
import '../../models/child_options.dart';
import '../../widgets/custom_bottom_nav.dart';
import '../parent/task_management_screen.dart';
import '../auth_wrapper.dart';
import 'setup_child_screen.dart';
import 'child_profile_view_screen.dart';
import 'parent_leaderboard_screen.dart';
import '../services/notification_service.dart';
import 'dart:io';
import 'parent_wishlist_screen.dart';
import 'setup_weekly_allowance_screen.dart';
import 'package:image_picker/image_picker.dart';

class ParentProfileScreen extends StatefulWidget {
  const ParentProfileScreen({super.key});

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen>
    with WidgetsBindingObserver {
  ParentProfile? _parentProfile;
  List<ChildOption> _children = [];
  String _parentUsername = ''; // ✅ store parent's username from Firestore
  bool _isExpanded = false;
  bool _isEditing = false;
  bool _isLoadingProfile = true;
  StreamSubscription<QuerySnapshot>? _childrenSubscription;
  final NotificationService _notificationService = NotificationService();

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  File? _selectedImage;

  Map<String, String?> _fieldErrors = {};

  /// ✅ Shortcut to get current logged-in UID
  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User is not authenticated. Please log in again.');
    }
    return user.uid;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isLoadingProfile = true;
    _parentProfile = null; // Reset profile when initializing
    _loadParentProfile();
    _setupChildrenListener();

    // Initialize notifications for the parent role
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: avoid_print
      print(
        '🎯 PostFrameCallback: Starting parent notification initialization...',
      );
      _notificationService
          .initializeForParent(parentId: _uid)
          .then((_) {
            // ignore: avoid_print
            print('🎯 Parent notification initialization completed');
          })
          .catchError((error, stackTrace) {
            // ignore: avoid_print
            print('❌ ===== FAILED TO INITIALIZE PARENT NOTIFICATIONS =====');
            // ignore: avoid_print
            print('❌ Error: $error');
            // ignore: avoid_print
            print('❌ Stack: $stackTrace');
          });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-setup listener if it was lost (e.g., after returning from another screen)
    if (_childrenSubscription == null || _childrenSubscription!.isPaused) {
      print('=== RE-SETUP CHILDREN LISTENER ===');
      _setupChildrenListener();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _childrenSubscription?.cancel();
    _notificationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Real-time listener will handle updates automatically
      print('App resumed, real-time listener is active');
    }
  }

  // Set up real-time listener for children
  void _setupChildrenListener() {
    print('=== SETTING UP REAL-TIME CHILDREN LISTENER ===');
    print('Parent UID: $_uid');

    _childrenSubscription?.cancel(); // Cancel existing subscription

    _childrenSubscription = FirebaseFirestore.instance
        .collection("Parents")
        .doc(_uid)
        .collection("Children")
        .snapshots(
          includeMetadataChanges: true,
        ) // Include metadata changes to catch all updates
        .listen(
          (QuerySnapshot snapshot) {
            print('=== REAL-TIME UPDATE RECEIVED ===');
            print('Snapshot size: ${snapshot.docs.length}');
            print('Has pending writes: ${snapshot.metadata.hasPendingWrites}');
            print('Is from cache: ${snapshot.metadata.isFromCache}');

            final childrenList = snapshot.docs
                .map((doc) {
                  print('Processing child doc: ${doc.id}');
                  final childData = doc.data() as Map<String, dynamic>?;
                  print('Child data: $childData');

                  if (childData == null) {
                    print('⚠️ Child data is null for ${doc.id}');
                    return null;
                  }

                  try {
                    final childOption = ChildOption.fromFirestore(
                      doc.id,
                      childData,
                    );
                    print(
                      'Created ChildOption: ID=${childOption.id}, firstName="${childOption.firstName}", username=${childOption.username}',
                    );
                    return childOption;
                  } catch (e) {
                    print('❌ Error creating ChildOption from ${doc.id}: $e');
                    return null;
                  }
                })
                .where((c) => c != null)
                .cast<ChildOption>()
                .where((c) {
                  final hasName = c.firstName.trim().isNotEmpty;
                  print(
                    'Child "${c.firstName}" (ID: ${c.id}) has valid name: $hasName',
                  );
                  if (!hasName) {
                    print('⚠️ Filtering out child ${c.id} - empty firstName');
                  }
                  return hasName;
                })
                .toList();

            print('Filtered to ${childrenList.length} children');
            print(
              'Children names: ${childrenList.map((c) => c.firstName).toList()}',
            );

            if (mounted) {
              setState(() {
                _children = childrenList;
              });
              print('=== CHILDREN LIST UPDATED IN REAL-TIME ===');
              print('New children count: ${_children.length}');
              print(
                'Children in state: ${_children.map((c) => '${c.firstName} (${c.id})').toList()}',
              );
            } else {
              print('Widget not mounted, skipping setState');
            }
          },
          onError: (error, stackTrace) {
            print('❌ Error in children listener: $error');
            print('Stack trace: $stackTrace');
            if (mounted) {
              _showToast(
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

    print('✅ Children listener set up successfully');
  }

  // Fill the editing controllers from the loaded _parentProfile.
  void _populateControllers() {
    if (_parentProfile == null) return;
    _firstNameController.text = _parentProfile!.firstName;
    _lastNameController.text = _parentProfile!.lastName;
  }

  Future<void> _loadParentProfile() async {
    try {
      print('=== LOADING PARENT PROFILE ===');
      print('Parent UID: $_uid');

      // ✅ Fetch parent document
      final doc = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid)
          .get();

      print('Document exists: ${doc.exists}');

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        print('Document data keys: ${data.keys.toList()}');

        setState(() {
          // Load parent profile object (existing behavior)
          _parentProfile = ParentProfile.fromFirestore(doc.id, data);
          _parentUsername = data['username'] ?? '';

          // ✅ Also extract parent username for child setup flow
          _parentUsername = data['username'] ?? '';
          _isLoadingProfile = false;
        });
        print('✅ Profile loaded successfully');

        // Auto-migrate orphaned children from top-level collection
        _migrateOrphanedChildren();
      } else {
        // Document doesn't exist - try to create it from Firebase Auth data
        print(
          '⚠️ Parent document does not exist, attempting to create from Auth data...',
        );
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != null) {
          print('Firebase Auth user exists: ${user.email}');

          try {
            // Create parent document with minimal data from Auth
            final displayNameParts = user.displayName?.split(' ') ?? [];
            await FirebaseFirestore.instance
                .collection("Parents")
                .doc(_uid)
                .set(
                  {
                    'firstName': displayNameParts.isNotEmpty
                        ? displayNameParts.first
                        : 'User',
                    'lastName': displayNameParts.length > 1
                        ? displayNameParts.skip(1).join(' ')
                        : '',
                    'username': user.email!.split('@').first,
                    'email': user.email!,
                    'phoneNumber': user.phoneNumber ?? '',
                    'avatar': null,
                    'createdAt': FieldValue.serverTimestamp(),
                    'role': 'parent',
                  },
                  SetOptions(merge: true),
                ); // Use merge to avoid overwriting if exists

            // Reload profile after creating
            print('✅ Parent document created, reloading profile...');
            await _loadParentProfile();
          } catch (createError) {
            print('❌ Error creating parent document: $createError');
            setState(() {
              _isLoadingProfile = false;
            });
            _showToast(
              'Error creating profile. Please contact support.',
              ToastificationType.error,
            );
          }
        } else {
          setState(() {
            _isLoadingProfile = false;
          });
          _showToast(
            'Not authenticated. Please log in again.',
            ToastificationType.error,
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error loading profile: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _isLoadingProfile = false;
      });
      _showToast('Error loading profile: $e', ToastificationType.error);
    }
    _populateControllers();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final updatedProfile = _parentProfile!.copyWith(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid) // ✅ use UID instead of "parent001"
          .update(updatedProfile.toFirestore());

      setState(() {
        _parentProfile = updatedProfile;
        _isEditing = false;
      });

      _showToast('Profile updated successfully', ToastificationType.success);
    } catch (e) {
      _showToast('Error updating profile: $e', ToastificationType.error);
    }
  }

  void _cancelEdit() {
    _populateControllers(); // 👈 restore form fields to current profile
    setState(() {
      _isEditing = false;
      _selectedImage = null;
      _fieldErrors.clear();
    });
  }

  /// Migrate orphaned children from top-level Children collection to parent subcollection
  /// This fixes existing children that were created before the subcollection structure was implemented
  Future<void> _migrateOrphanedChildren() async {
    try {
      print('🔄 Starting automatic migration of orphaned children...');

      // Find all children in top-level Children collection
      // We need to check which ones belong to this parent by checking the parent reference
      final allChildren = await FirebaseFirestore.instance
          .collection('Children')
          .get();

      print(
        'Found ${allChildren.docs.length} children in top-level collection',
      );
      print('Current parent UID: $_uid');
      print('Current parent path: Parents/$_uid');

      int migratedCount = 0;
      final parentRef = FirebaseFirestore.instance
          .collection('Parents')
          .doc(_uid);
      final parentChildrenRef = parentRef.collection('Children');
      final expectedParentPath = 'Parents/$_uid';
      final expectedParentPathWithSlash = '/Parents/$_uid';

      for (var childDoc in allChildren.docs) {
        final childData = childDoc.data();
        final childId = childDoc.id;
        final username = childData['username'] ?? 'N/A';

        print('   Checking child: $childId (username: $username)');

        // Check if this child belongs to the current parent
        final parentField = childData['parent'];
        bool belongsToThisParent = false;

        if (parentField == null) {
          print('   ⚠️ Child has no parent field, skipping');
          continue;
        }

        if (parentField is DocumentReference) {
          final parentPath = parentField.path;
          belongsToThisParent =
              parentPath == expectedParentPath ||
              parentPath == expectedParentPathWithSlash;
          print('   Parent reference (DocumentReference): $parentPath');
        } else if (parentField is String) {
          final parentPath = parentField.trim();
          // Check multiple possible formats
          belongsToThisParent =
              parentPath == expectedParentPath ||
              parentPath == expectedParentPathWithSlash ||
              parentPath.contains(_uid) ||
              parentPath.endsWith('/$_uid');
          print('   Parent reference (String): "$parentPath"');
        } else {
          print(
            '   ⚠️ Unexpected parent field type: ${parentField.runtimeType}',
          );
        }

        print('   → Belongs to this parent: $belongsToThisParent');

        if (!belongsToThisParent) {
          continue; // Skip children that don't belong to this parent
        }

        // Check if child already exists in parent subcollection
        final existingInSubcollection = await parentChildrenRef
            .doc(childId)
            .get();

        if (!existingInSubcollection.exists) {
          print(
            '📦 Migrating child: $childId (username: ${childData['username']})',
          );

          // Copy child data to parent subcollection
          // Map the data from top-level collection format to subcollection format
          final migratedData = {
            'firstName': childData['firstName'] ?? '',
            'username': childData['username'] ?? '',
            'username_lc':
                (childData['username'] as String?)?.toLowerCase() ?? '',
            'email': (childData['email'] as String?)?.toLowerCase() ?? '',
            'active': true,
            'role': 'child',
            'level': childData['level'] ?? 1,
            'completedLessons': childData['completedLessons'] ?? [],
            'lastCompletedLesson': childData['lastCompletedLesson'],
            'lastCompletionTime': childData['lastCompletionTime'],
            'createdAt': childData['createdAt'] ?? FieldValue.serverTimestamp(),
            // Note: pin_hash and pin_salt won't be in top-level collection
            // This is okay - existing Firebase Auth account will work for login
          };

          await parentChildrenRef.doc(childId).set(migratedData);
          migratedCount++;
          print(
            '✅ Migrated child $childId (username: ${childData['username']})',
          );
        } else {
          print('⏭️ Child $childId already exists in subcollection, skipping');
        }
      }

      if (migratedCount > 0) {
        print('✅ Migration complete: $migratedCount children migrated');
        // Show a subtle notification that children were migrated
        _showToast(
          'Migrated $migratedCount child account(s) for login',
          ToastificationType.success,
        );
      } else {
        print('✅ No children needed migration');
      }
    } catch (e) {
      print('⚠️ Error during migration (non-critical): $e');
      // Don't show error to user - migration is best-effort
    }
  }

  void _showToast(String message, ToastificationType type) {
    toastification.show(
      context: context,
      type: type,
      style: ToastificationStyle.fillColored,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  void _onNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        // Already on Profile
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentLeaderboardScreen()),
        );
        break;
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      _showToast('Error picking image: $e', ToastificationType.error);
    }
  }

  void _validateField(String fieldType, String value) {
    String? errorMessage;

    switch (fieldType) {
      case 'firstName':
        errorMessage = ParentProfile.validateFirstName(value);
        break;
      case 'lastName':
        errorMessage = ParentProfile.validateLastName(value);
        break;
    }

    setState(() {
      _fieldErrors[fieldType] = errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth >= 600;
    final isDesktop = screenWidth >= 1024;
    final isSmallScreen = screenHeight < 600;
    final isLargeScreen = screenWidth >= 1200;
    final isExtraSmallScreen = screenWidth < 360;

    // 🧠 If still loading, show a loading screen
    if (_isLoadingProfile) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF7C3AED),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Loading profile...',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 🧠 If _parentProfile is null after loading, show error state
    if (_parentProfile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 64.sp,
                  color: const Color(0xFFEF4444),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Profile Not Found',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Unable to load your profile. Please try again later.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: const Color(0xFF64748B),
                  ),
                ),
                SizedBox(height: 24.h),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoadingProfile = true;
                    });
                    _loadParentProfile();
                  },
                  icon: Icon(Icons.refresh_rounded, size: 18.sp),
                  label: Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.w,
                      vertical: 12.h,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ Once data is loaded, build the actual UI
    return Scaffold(
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
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isLargeScreen
                  ? 64.w
                  : isDesktop
                  ? 48.w
                  : isTablet
                  ? 32.w
                  : isExtraSmallScreen
                  ? 12.w
                  : 16.w,
              vertical: isSmallScreen ? 12.h : 20.h,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLargeScreen
                    ? 1000.w
                    : isDesktop
                    ? 800.w
                    : isTablet
                    ? 600.w
                    : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGamifiedProfileSection(
                    isTablet,
                    isDesktop,
                    isSmallScreen,
                    isLargeScreen,
                    isExtraSmallScreen,
                  ),
                  SizedBox(height: 16.h),
                  _buildWeeklyAllowanceButton(),
                  SizedBox(height: 20.h),
                  _buildGamifiedChildrenSection(
                    isTablet,
                    isDesktop,
                    isSmallScreen,
                    isLargeScreen,
                    isExtraSmallScreen,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 0,
        onTap: (index) => _onNavTap(context, index),
      ),
    );
  }

  Widget _buildProfileDetails() {
    return Column(
      children: [
        _buildDetailRow('First Name', _parentProfile!.firstName),
        _buildDetailRow('Last Name', _parentProfile!.lastName),
        _buildDetailRow('Username', _parentProfile!.username),
        _buildDetailRow('Email', _parentProfile!.email),
        _buildDetailRow('Phone Number', _parentProfile!.phoneNumber),
        SizedBox(height: 20.h),
        // Logout button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _showLogoutDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.8),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              padding: EdgeInsets.symmetric(vertical: 12.h),
            ),
            icon: Icon(Icons.logout, size: 18.sp),
            label: Text(
              'Logout',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100.w,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamifiedProfileSection(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
    bool isLargeScreen,
    bool isExtraSmallScreen,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667EEA), // Vibrant blue
            Color(0xFF764BA2), // Rich purple
            Color(0xFFF093FB), // Pink accent
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(
          isLargeScreen
              ? 32.r
              : isDesktop
              ? 28.r
              : isTablet
              ? 24.r
              : 20.r,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFF764BA2).withOpacity(0.2),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(
              isLargeScreen
                  ? 32.w
                  : isDesktop
                  ? 24.w
                  : isTablet
                  ? 20.w
                  : isExtraSmallScreen
                  ? 12.w
                  : 16.w,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Enhanced avatar with glass effect
                GestureDetector(
                  onTap: _isEditing ? _pickImage : null,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: isLargeScreen
                          ? 50.r
                          : isDesktop
                          ? 45.r
                          : isTablet
                          ? 40.r
                          : isSmallScreen
                          ? 28.r
                          : isExtraSmallScreen
                          ? 25.r
                          : 35.r,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: isLargeScreen
                              ? 48.r
                              : isDesktop
                              ? 43.r
                              : isTablet
                              ? 38.r
                              : isSmallScreen
                              ? 26.r
                              : isExtraSmallScreen
                              ? 23.r
                              : 33.r,
                          backgroundColor: Colors.transparent,
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (_parentProfile?.avatar != null
                                        ? NetworkImage(_parentProfile!.avatar!)
                                        : null)
                                    as ImageProvider<Object>?,
                          child:
                              _selectedImage == null &&
                                  (_parentProfile?.avatar == null)
                              ? Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: isLargeScreen
                                      ? 40.sp
                                      : isDesktop
                                      ? 35.sp
                                      : isTablet
                                      ? 30.sp
                                      : isSmallScreen
                                      ? 18.sp
                                      : isExtraSmallScreen
                                      ? 16.sp
                                      : 25.sp,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: isLargeScreen
                      ? 24.w
                      : isDesktop
                      ? 20.w
                      : isTablet
                      ? 16.w
                      : isExtraSmallScreen
                      ? 8.w
                      : 12.w,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${_parentProfile!.firstName}!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isLargeScreen
                              ? 32.sp
                              : isDesktop
                              ? 28.sp
                              : isTablet
                              ? 26.sp
                              : isSmallScreen
                              ? 18.sp
                              : isExtraSmallScreen
                              ? 16.sp
                              : 24.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.2),
                              offset: const Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 12.w : 10.w,
                          vertical: isDesktop ? 4.h : 3.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(
                            isDesktop ? 12.r : 10.r,
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Family Manager',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isDesktop ? 12.sp : 10.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Enhanced expand button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(
                      isDesktop ? 12.r : 10.r,
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: isDesktop
                          ? 28.sp
                          : isTablet
                          ? 26.sp
                          : isSmallScreen
                          ? 20.sp
                          : 24.sp,
                    ),
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  ),
                ),
              ],
            ),
          ),

          // 👇 Expandable Profile Info / Edit Section
          if (_isExpanded)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop
                    ? 24.w
                    : isTablet
                    ? 20.w
                    : 16.w,
                vertical: 8.h,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Profile Information',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isDesktop ? 18.sp : 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_isEditing)
                        TextButton.icon(
                          onPressed: () => setState(() => _isEditing = true),
                          icon: Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 16.sp,
                          ),
                          label: Text(
                            'Edit',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isDesktop ? 14.sp : 12.sp,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  _isEditing ? _buildEditForm() : _buildProfileDetails(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildTextField(
            controller: _firstNameController,
            label: 'First Name',
            validator: ParentProfile.validateFirstName,
            onChanged: (v) => _validateField('firstName', v),
            fieldType: 'firstName',
          ),
          _buildTextField(
            controller: _lastNameController,
            label: 'Last Name',
            validator: ParentProfile.validateLastName,
            onChanged: (v) => _validateField('lastName', v),
            fieldType: 'lastName',
          ),
          _buildNonEditableField(
            label: 'Username',
            value: _parentProfile!.username,
            message: 'Username cannot be changed',
          ),
          _buildNonEditableField(
            label: 'Email',
            value: _parentProfile!.email,
            message: 'Email cannot be changed',
          ),
          _buildNonEditableField(
            label: 'Phone Number',
            value: _parentProfile!.phoneNumber,
            message: 'Phone number cannot be changed',
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.5)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF8B5CF6),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    String? fieldType,
    TextInputType? keyboardType,
    bool obscureText = false,
    Function(String)? onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        style: TextStyle(color: Colors.white, fontSize: 12.sp),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12.sp,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: BorderSide(
              color: _fieldErrors[fieldType] != null
                  ? Colors.red
                  : Colors.white.withOpacity(0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: BorderSide(
              color: _fieldErrors[fieldType] != null
                  ? Colors.red
                  : Colors.white,
            ),
          ),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildNonEditableField({
    required String label,
    required String value,
    required String message,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12.sp,
            ),
          ),
          SizedBox(height: 4.h),
          GestureDetector(
            onTap: () {
              _showToast(message, ToastificationType.info);
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamifiedChildrenSection(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
    bool isLargeScreen,
    bool isExtraSmallScreen,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gamified header with glass effect
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLargeScreen
                ? 32.w
                : isDesktop
                ? 24.w
                : isTablet
                ? 20.w
                : isExtraSmallScreen
                ? 12.w
                : 16.w,
            vertical: isLargeScreen
                ? 24.h
                : isDesktop
                ? 20.h
                : isTablet
                ? 16.h
                : isExtraSmallScreen
                ? 8.h
                : 12.h,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(
              isLargeScreen
                  ? 24.r
                  : isDesktop
                  ? 20.r
                  : isTablet
                  ? 16.r
                  : 14.r,
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 20,
                offset: const Offset(0, -2),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isDesktop ? 12.w : 10.w),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        isDesktop ? 14.r : 12.r,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.family_restroom_rounded,
                      color: Colors.white,
                      size: isDesktop
                          ? 24.sp
                          : isTablet
                          ? 22.sp
                          : 18.sp,
                    ),
                  ),
                  SizedBox(width: isDesktop ? 16.w : 12.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Children',
                        style: TextStyle(
                          fontSize: isDesktop
                              ? 24.sp
                              : isTablet
                              ? 22.sp
                              : isSmallScreen
                              ? 18.sp
                              : 20.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                          letterSpacing: 0.3,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'View their wallets & information',
                        style: TextStyle(
                          fontSize: isDesktop ? 12.sp : 10.sp,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (_children.isNotEmpty) ...[
                    SizedBox(width: isDesktop ? 12.w : 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 12.w : 10.w,
                        vertical: isDesktop ? 6.h : 4.h,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(
                          isDesktop ? 16.r : 14.r,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        '${_children.length}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isDesktop ? 14.sp : 12.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(
                      isLargeScreen
                          ? 18.r
                          : isDesktop
                          ? 16.r
                          : isTablet
                          ? 14.r
                          : 12.r,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        isLargeScreen
                            ? 18.r
                            : isDesktop
                            ? 16.r
                            : isTablet
                            ? 14.r
                            : 12.r,
                      ),
                      onTap: () async {
                        // Check if user is authenticated before navigating
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please log in again to add a child',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          return;
                        }

                        print(
                          '=== NAVIGATING TO SETUP CHILD SCREEN (Add Button) ===',
                        );
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SetupChildScreen(
                              parentId: currentUser.uid,
                              parentUsername: _parentUsername,
                            ),
                          ),
                        );
                        print(
                          '=== RETURNED FROM SETUP CHILD SCREEN (Add Button) ===',
                        );
                        // Force refresh of children list when returning from child creation
                        if (mounted) {
                          print(
                            'Refreshing children listener after returning from setup...',
                          );
                          _setupChildrenListener(); // Always refresh to ensure new child appears
                        }
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen
                              ? 20.w
                              : isDesktop
                              ? 16.w
                              : isTablet
                              ? 14.w
                              : isExtraSmallScreen
                              ? 8.w
                              : 12.w,
                          vertical: isLargeScreen
                              ? 16.h
                              : isDesktop
                              ? 14.h
                              : isTablet
                              ? 12.h
                              : isExtraSmallScreen
                              ? 8.h
                              : 10.h,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: isLargeScreen
                                  ? 22.sp
                                  : isDesktop
                                  ? 20.sp
                                  : isTablet
                                  ? 18.sp
                                  : isExtraSmallScreen
                                  ? 14.sp
                                  : 16.sp,
                            ),
                            SizedBox(
                              width: isLargeScreen
                                  ? 10.w
                                  : isDesktop
                                  ? 8.w
                                  : isTablet
                                  ? 6.w
                                  : isExtraSmallScreen
                                  ? 4.w
                                  : 5.w,
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
        ),
        SizedBox(
          height: isDesktop
              ? 20.h
              : isTablet
              ? 16.h
              : 12.h,
        ),

        // Children list or empty state
        if (_children.isEmpty)
          _buildGamifiedEmptyState(
            isTablet,
            isDesktop,
            isSmallScreen,
            isLargeScreen,
            isExtraSmallScreen,
          )
        else
          _buildGamifiedChildrenList(
            isTablet,
            isDesktop,
            isSmallScreen,
            isLargeScreen,
            isExtraSmallScreen,
          ),
      ],
    );
  }

  Widget _buildGamifiedEmptyState(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
    bool isLargeScreen,
    bool isExtraSmallScreen,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isLargeScreen
            ? 56.w
            : isDesktop
            ? 48.w
            : isTablet
            ? 40.w
            : isSmallScreen
            ? 28.w
            : isExtraSmallScreen
            ? 24.w
            : 32.w,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.9),
            Colors.white.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isDesktop ? 24.r : 20.r),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.8),
            blurRadius: 20,
            offset: const Offset(0, -4),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 32.w : 28.w),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF667EEA),
                  Color(0xFF764BA2),
                  Color(0xFFF093FB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.child_care_rounded,
              size: isDesktop
                  ? 56.sp
                  : isTablet
                  ? 48.sp
                  : isSmallScreen
                  ? 36.sp
                  : 42.sp,
              color: Colors.white,
            ),
          ),
          SizedBox(
            height: isDesktop
                ? 24.h
                : isTablet
                ? 20.h
                : 16.h,
          ),
          Text(
            'No children yet',
            style: TextStyle(
              fontSize: isDesktop
                  ? 24.sp
                  : isTablet
                  ? 22.sp
                  : isSmallScreen
                  ? 18.sp
                  : 20.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: isDesktop ? 8.h : 6.h),
          Text(
            'Add your first child to start managing\ntheir tasks and rewards',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isDesktop
                  ? 16.sp
                  : isTablet
                  ? 15.sp
                  : isSmallScreen
                  ? 13.sp
                  : 14.sp,
              color: const Color(0xFF64748B),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamifiedChildrenList(
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
    bool isLargeScreen,
    bool isExtraSmallScreen,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _children.length,
      itemBuilder: (context, index) {
        return _buildGamifiedChildCard(
          _children[index],
          isTablet,
          isDesktop,
          isSmallScreen,
          isLargeScreen,
          isExtraSmallScreen,
        );
      },
    );
  }

  Widget _buildGamifiedChildCard(
    ChildOption child,
    bool isTablet,
    bool isDesktop,
    bool isSmallScreen,
    bool isLargeScreen,
    bool isExtraSmallScreen,
  ) {
    // Mock data for gamification - in real app, this would come from Firebase
    final childIndex = _children.indexOf(child);

    return Container(
      margin: EdgeInsets.only(
        bottom: isLargeScreen
            ? 24.h
            : isDesktop
            ? 20.h
            : isTablet
            ? 18.h
            : isSmallScreen
            ? 12.h
            : isExtraSmallScreen
            ? 10.h
            : 16.h,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.95),
            Colors.white.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          isLargeScreen
              ? 24.r
              : isDesktop
              ? 20.r
              : isTablet
              ? 18.r
              : 16.r,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 10),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.9),
            blurRadius: 20,
            offset: const Offset(0, -4),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(isDesktop ? 20.r : 18.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(isDesktop ? 20.r : 18.r),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ChildProfileViewScreen(child: child, parentId: _uid),
              ),
            );
          },
          child: Container(
            padding: EdgeInsets.all(
              isLargeScreen
                  ? 28.w
                  : isDesktop
                  ? 24.w
                  : isTablet
                  ? 20.w
                  : isSmallScreen
                  ? 14.w
                  : isExtraSmallScreen
                  ? 12.w
                  : 18.w,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Enhanced avatar with glow effect
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667EEA).withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: isLargeScreen
                            ? 40.r
                            : isDesktop
                            ? 36.r
                            : isTablet
                            ? 32.r
                            : isSmallScreen
                            ? 24.r
                            : isExtraSmallScreen
                            ? 22.r
                            : 30.r,
                        backgroundColor: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF667EEA),
                                const Color(0xFF764BA2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: child.avatar != null
                              ? ClipOval(
                                  child: Image.network(
                                    child.avatar!,
                                    width:
                                        (isDesktop
                                            ? 36.r
                                            : isTablet
                                            ? 32.r
                                            : isSmallScreen
                                            ? 28.r
                                            : 30.r) *
                                        2,
                                    height:
                                        (isDesktop
                                            ? 36.r
                                            : isTablet
                                            ? 32.r
                                            : isSmallScreen
                                            ? 28.r
                                            : 30.r) *
                                        2,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) {
                                      return Center(
                                        child: Text(
                                          child.initial,
                                          style: TextStyle(
                                            fontSize: isDesktop
                                                ? 22.sp
                                                : isTablet
                                                ? 20.sp
                                                : isSmallScreen
                                                ? 16.sp
                                                : 18.sp,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
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
                                      fontSize: isDesktop
                                          ? 22.sp
                                          : isTablet
                                          ? 20.sp
                                          : isSmallScreen
                                          ? 16.sp
                                          : 18.sp,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    SizedBox(width: isDesktop ? 20.w : 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            child.firstName,
                            style: TextStyle(
                              fontSize: isDesktop
                                  ? 20.sp
                                  : isTablet
                                  ? 18.sp
                                  : isSmallScreen
                                  ? 16.sp
                                  : 17.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E293B),
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(height: isDesktop ? 4.h : 3.h),
                          Text(
                            child.lastName,
                            style: TextStyle(
                              fontSize: isDesktop
                                  ? 14.sp
                                  : isTablet
                                  ? 13.sp
                                  : isSmallScreen
                                  ? 11.sp
                                  : 12.sp,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Gamified stats badges
                    // (Removed stats badges)
                    SizedBox.shrink(),
                  ],
                ),
                SizedBox(height: isDesktop ? 16.h : 14.h),

                // Progress bar
                SizedBox(height: isDesktop ? 12.h : 10.h),
                // Action button
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 16.w : 14.w,
                    vertical: isDesktop ? 12.h : 10.h,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF667EEA).withOpacity(0.1),
                        const Color(0xFF764BA2).withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(
                      isDesktop ? 12.r : 10.r,
                    ),
                    border: Border.all(
                      color: const Color(0xFF667EEA).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_rounded,
                        color: const Color(0xFF667EEA),
                        size: isDesktop ? 16.sp : 14.sp,
                      ),
                      SizedBox(width: isDesktop ? 8.w : 6.w),
                      Text(
                        'View Profile',
                        style: TextStyle(
                          fontSize: isDesktop ? 14.sp : 12.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF667EEA),
                          letterSpacing: 0.3,
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
    );
  }

  Widget _buildWeeklyAllowanceButton() {
    final isDisabled = _children.isEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SetUpWeeklyAllowanceScreen(children: _children),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(20.r),
        child: Opacity(
          opacity: isDisabled ? 0.6 : 1.0,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF5F6FF), // Very light blue
                  Color(0xFFECEFFE), // Light blue
                ],
              ),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: const Color(0xFFE8EAFE), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.09),
                  blurRadius: 18,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon container with gradient
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFA28BFE), // Purple
                        Color(0xFF8F5CFF), // Darker purple
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA28BFE).withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 20.sp,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 16.w),
                // Title text
                Expanded(
                  child: Text(
                    'Set Up Weekly Allowance',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1C1243),
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

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          title: Row(
            children: [
              Icon(Icons.logout, color: Colors.red, size: 24.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to log out of your account?',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
          actionsPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog first
                try {
                  await FirebaseAuth.instance.signOut();

                  if (!mounted) return;

                  // ✅ Return to AuthWrapper directly
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthWrapper()),
                    (route) => false,
                  );
                } catch (e) {
                  _showToast('Error logging out: $e', ToastificationType.error);
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              label: Text('Logout', style: TextStyle(fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
  }
}
