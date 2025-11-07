import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:toastification/toastification.dart';

import '../../widgets/custom_bottom_nav.dart';
import '../../models/child_options.dart';
import 'child_wishlist_details_screen.dart';
import 'parent_profile_screen.dart';
import 'task_management_screen.dart';
import 'parent_leaderboard_screen.dart';

class ParentWishlistScreen extends StatefulWidget {
  final String parentId;

  const ParentWishlistScreen({super.key, required this.parentId});

  @override
  State<ParentWishlistScreen> createState() => _ParentWishlistScreenState();
}

class _ParentWishlistScreenState extends State<ParentWishlistScreen>
    with SingleTickerProviderStateMixin {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  List<ChildOption> _children = [];
  Map<String, int> _wishlistCounts = {};
  Map<String, int> _purchasedCounts = {}; // Track purchased items per child
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadChildren();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
        // Already on Wishlist
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentLeaderboardScreen()),
        );
        break;
    }
  }

  Future<void> _loadChildren() async {
    try {
      setState(() => _isLoading = true);

      // 1️⃣ Fetch all children at once
      final childrenSnap = await FirebaseFirestore.instance
          .collection("Parents")
          .doc(_uid)
          .collection("Children")
          .get();

      final childrenList = childrenSnap.docs
          .map((doc) => ChildOption.fromFirestore(doc.id, doc.data()))
          .where((c) => c.firstName.trim().isNotEmpty)
          .toList();

      if (childrenList.isEmpty) {
        setState(() {
          _children = [];
          _wishlistCounts = {};
          _purchasedCounts = {};
          _isLoading = false;
        });
        return;
      }

      // 2️⃣ Prepare all wishlist queries (run in parallel)
      final wishlistFutures = childrenList.map((child) async {
        final wishlistSnap = await FirebaseFirestore.instance
            .collection("Parents")
            .doc(_uid)
            .collection("Children")
            .doc(child.id)
            .collection("Wishlist")
            .get();

        final totalCount = wishlistSnap.size;
        final purchasedCount = wishlistSnap.docs.where((doc) {
          final data = doc.data();
          return data['isPurchased'] == true;
        }).length;

        return {
          "childId": child.id,
          "total": totalCount,
          "purchased": purchasedCount,
        };
      }).toList();

      // 3️⃣ Await all parallel queries
      final wishlistResults = await Future.wait(wishlistFutures);

      // 4️⃣ Build count maps efficiently
      final counts = <String, int>{};
      final purchasedCounts = <String, int>{};

      for (final result in wishlistResults) {
        final childId = result["childId"] as String;
        final total = result["total"] as int;
        final purchased = result["purchased"] as int;

        counts[childId] = total;
        purchasedCounts[childId] = purchased;
      }

      // 5️⃣ Update state once at the end
      setState(() {
        _children = childrenList;
        _wishlistCounts = counts;
        _purchasedCounts = purchasedCounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading children: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final crossAxisCount = isTablet ? 2 : 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 2,
        onTap: (index) => _onNavTap(context, index),
      ),
      body: Column(
        children: [
          // Custom Navigation Bar with Gradient
          Container(
            width: double.infinity, // 👈 Force full width
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF643FDB), const Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24.r),
                bottomRight: Radius.circular(24.r),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF643FDB).withOpacity(0.3),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: Offset(0, 6.h),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: Offset(0, 2.h),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 22.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Wishlist',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    // Subtle Accent Line with shimmer effect
                    Container(
                      width: 48.w,
                      height: 3.h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.8),
                            Colors.white.withOpacity(0.4),
                            Colors.white.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 4,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Children Wishlist Content
          Expanded(
            child: _isLoading
                ? Center(
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
                          'Loading wishlists...',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  )
                : _children.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadChildren,
                    color: const Color(0xFF7C3AED),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (isTablet) {
                          // Grid layout for tablets
                          return GridView.builder(
                            padding: EdgeInsets.only(
                              top: 16.h,
                              left: 20.w,
                              right: 20.w,
                              bottom: 80.h, // Padding for bottom nav bar
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: 2.5,
                                  crossAxisSpacing: 16.w,
                                  mainAxisSpacing: 24.h,
                                ),
                            itemCount: _children.length,
                            itemBuilder: (context, index) {
                              final child = _children[index];
                              final wishlistCount =
                                  _wishlistCounts[child.id] ?? 0;
                              final purchasedCount =
                                  _purchasedCounts[child.id] ?? 0;
                              return _buildChildCard(
                                child,
                                wishlistCount,
                                purchasedCount,
                              );
                            },
                          );
                        } else {
                          // List layout for mobile
                          return ListView.builder(
                            padding: EdgeInsets.only(
                              top: 16.h,
                              left: 20.w,
                              right: 20.w,
                              bottom: 80.h, // Padding for bottom nav bar
                            ),
                            itemCount: _children.length,
                            itemBuilder: (context, index) {
                              final child = _children[index];
                              final wishlistCount =
                                  _wishlistCounts[child.id] ?? 0;
                              final purchasedCount =
                                  _purchasedCounts[child.id] ?? 0;
                              return _buildChildCard(
                                child,
                                wishlistCount,
                                purchasedCount,
                              );
                            },
                          );
                        }
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildCard(
    ChildOption child,
    int wishlistCount,
    int purchasedCount,
  ) {
    final hasPurchased = purchasedCount > 0;
    return Container(
      margin: EdgeInsets.only(bottom: 24.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            // Scale animation on tap - slight delay for visual feedback
            await Future.delayed(const Duration(milliseconds: 100));
            await Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    ChildWishlistDetailsScreen(
                      parentId: _uid,
                      childId: child.id,
                      childName: child.fullName,
                    ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0.0, 0.1),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: child,
                        ),
                      );
                    },
              ),
            ).then((_) {
              // Refresh data when returning from child details
              _loadChildren();
            });
          },
          borderRadius: BorderRadius.circular(22.r),
          splashColor: const Color(0xFF643FDB).withOpacity(0.15),
          highlightColor: const Color(0xFF8B5CF6).withOpacity(0.08),
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, const Color(0xFFF8FAFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              color: Colors.white,
              borderRadius: BorderRadius.circular(22.r),
              border: Border.all(
                width: 2,
                color: const Color(0xFF643FDB).withOpacity(0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF643FDB).withOpacity(0.12),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: Offset(0, 6.h),
                ),
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.06),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: Offset(0, 2.h),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: Offset(0, 1.h),
                ),
              ],
            ),
            child: Row(
              children: [
                // Profile Picture
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF643FDB).withOpacity(0.15),
                            const Color(0xFF8B5CF6).withOpacity(0.12),
                          ],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 36.r,
                        backgroundColor: Colors.transparent,
                        child: child.avatar != null && child.avatar!.isNotEmpty
                            ? ClipOval(
                                child: Image.network(
                                  child.avatar!,
                                  width: 72.r,
                                  height: 72.r,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF643FDB,
                                        ).withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          child.initial,
                                          style: TextStyle(
                                            fontSize: 26.sp,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF643FDB),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF643FDB,
                                  ).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    child.initial,
                                    style: TextStyle(
                                      fontSize: 26.sp,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF643FDB),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 22.w),
                // Name and Wishlist Count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        child.fullName,
                        style: TextStyle(
                          fontSize: 19.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E1E2E),
                          letterSpacing: 0.1,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Row(
                        children: [
                          // Gradient Heart Icon
                          Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF643FDB),
                                  const Color(0xFF8B5CF6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.favorite_rounded,
                              size: 12.sp,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            '$wishlistCount item${wishlistCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFA0AEC0),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                      // Purchased Indicator
                      if (hasPurchased) ...[
                        SizedBox(height: 6.h),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 14.sp,
                              color: const Color(0xFF4A90E2),
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              '$purchasedCount Purchased',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF4A90E2),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Minimalist Chevron Icon
                Container(
                  padding: EdgeInsets.all(4.w),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: const Color(0xFFCBD5E1),
                    size: 20.sp,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(32.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF643FDB).withOpacity(0.1),
                  const Color(0xFF8B5CF6).withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Text('🎁', style: TextStyle(fontSize: 64.sp)),
          ),
          SizedBox(height: 24.h),
          Text(
            'No Wishlists Yet 💜',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E1E2E),
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Once your children add their first wish, it\'ll appear here!',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFFA0AEC0),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
