import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/wishlist_item.dart';
import '../../models/wallet.dart';
import '../services/wishlist_service.dart';
import '../services/haseela_service.dart';
import '../../widgets/custom_bottom_nav.dart';
import 'child_home_screen.dart';
import 'child_task_view_screen.dart';

class WishlistScreen extends StatefulWidget {
  final String parentId;
  final String childId;

  const WishlistScreen({
    Key? key,
    required this.parentId,
    required this.childId,
  }) : super(key: key);

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen>
    with TickerProviderStateMixin {
  int _navBarIndex = 2; // Wishlist tab index
  AnimationController? _sparkleController;
  double currentBalance = 0.0;
  StreamSubscription<Wallet?>? _walletSubscription;

  @override
  void initState() {
    super.initState();
    _sparkleController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _loadBalance();
  }

  @override
  void dispose() {
    _sparkleController?.dispose();
    _walletSubscription?.cancel();
    super.dispose();
  }

  void _loadBalance() {
    print(
      '🔍 WishlistScreen: Loading wallet balance for parentId: ${widget.parentId}, childId: ${widget.childId}',
    );
    _walletSubscription = HaseelaService()
        .getWalletForChild(widget.parentId, widget.childId)
        .listen(
          (wallet) {
            print('🔍 WishlistScreen: Wallet data received');
            if (mounted && wallet != null) {
              print(
                '🔍 WishlistScreen: Spending balance: ${wallet.spendingBalance}',
              );
              setState(() {
                currentBalance = wallet.spendingBalance;
              });
            } else {
              print('⚠️ WishlistScreen: Wallet is null or widget not mounted');
            }
          },
          onError: (error) {
            print('❌ WishlistScreen: Error loading wallet: $error');
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF643FDB),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // Disable back button
        title: Text(
          'My Wishlist',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Text',
          ),
        ),
        actions: [],
      ),
      body: StreamBuilder<Wallet?>(
        stream: HaseelaService().getWalletForChild(
          widget.parentId,
          widget.childId,
        ),
        builder: (context, walletSnapshot) {
          // Get the current balance from the wallet snapshot
          final wallet = walletSnapshot.hasData && walletSnapshot.data != null
              ? walletSnapshot.data!
              : null;
          final walletBalance = wallet?.spendingBalance ?? 0.0;

          return Column(
            children: [
              // Total Value Card
              _buildTotalValueCard(walletBalance),

              // Add Item Button
              _buildAddItemButton(),

              // Wishlist Items
              Expanded(child: _buildWishlistItems(walletBalance)),
            ],
          );
        },
      ),
      // Bottom navigation is handled by ChildMainWrapper
    );
  }

  Widget _buildTotalValueCard(double balance) {
    return Container(
      margin: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF643FDB), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF643FDB).withOpacity(0.4),
            blurRadius: 20.r,
            offset: Offset(0, 10.h),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -20.w,
            top: -20.h,
            child: Container(
              width: 100.w,
              height: 100.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            left: -10.w,
            bottom: -10.h,
            child: Container(
              width: 60.w,
              height: 60.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          // Main content
          Padding(
            padding: EdgeInsets.all(24.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Text('💝', style: TextStyle(fontSize: 32.sp)),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Total Wishlist Value",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.8),
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                      SizedBox(height: 4.h),
                      StreamBuilder<List<WishlistItem>>(
                        stream: WishlistService.getWishlistItems(
                          widget.parentId,
                          widget.childId,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            double total = 0.0;
                            for (var item in snapshot.data!) {
                              total += item.price;
                            }
                            return Text(
                              "${total.toStringAsFixed(2)} SAR",
                              style: TextStyle(
                                fontSize: 28.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: 'SF Pro Text',
                              ),
                            );
                          }
                          return Text(
                            "0.00 SAR",
                            style: TextStyle(
                              fontSize: 28.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'SF Pro Text',
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        "Spending Wallet",
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.7),
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        "${balance.toStringAsFixed(2)} SAR",
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemButton() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF643FDB), const Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF643FDB).withOpacity(0.3),
            blurRadius: 12.r,
            offset: Offset(0, 6.h),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showAddItemDialog(),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 24.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_circle_rounded,
                    size: 24.sp,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12.w),
                Text(
                  'Add item to wishlist',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'SF Pro Text',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWishlistItems(double balance) {
    return StreamBuilder<List<WishlistItem>>(
      stream: WishlistService.getWishlistItems(widget.parentId, widget.childId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF643FDB),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          print('❌ WishlistScreen: Error loading wishlist: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64.sp,
                  color: const Color(0xFFA29EB6),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Error loading wishlist',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1C1243),
                    fontFamily: 'SF Pro Text',
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF718096),
                    fontFamily: 'SF Pro Text',
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      // Trigger rebuild to retry
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF643FDB),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Retry',
                    style: TextStyle(fontFamily: 'SF Pro Text'),
                  ),
                ),
                SizedBox(height: 16.h),
                ElevatedButton(
                  onPressed: () => _showAddItemDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF47C272),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Add First Item',
                    style: TextStyle(fontFamily: 'SF Pro Text'),
                  ),
                ),
              ],
            ),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Fun animated empty state
                  Container(
                    padding: EdgeInsets.all(40.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF643FDB).withOpacity(0.1),
                          const Color(0xFF8B5CF6).withOpacity(0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Text('⭐', style: TextStyle(fontSize: 80.sp)),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    'Your Dream List Awaits! 🌟',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1C1243),
                      fontFamily: 'SF Pro Text',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'Start adding items you want to save up for!\nEvery completed task brings you closer 🎯',
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: const Color(0xFF718096),
                      fontFamily: 'SF Pro Text',
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 32.h),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _buildWishlistItemCard(item, balance);
          },
        );
      },
    );
  }

  Widget _buildWishlistItemCard(WishlistItem item, double balance) {
    // Get random fun gradient colors for each item
    final gradients = [
      [const Color(0xFFFF6B9D), const Color(0xFFC06C84)],
      [const Color(0xFF11998E), const Color(0xFF38EF7D)],
      [const Color(0xFFFFD89B), const Color(0xFF19547B)],
      [const Color(0xFFA8EDEA), const Color(0xFFFED6E3)],
      [const Color(0xFFFF9A56), const Color(0xFFFF6A88)],
      [const Color(0xFF667EEA), const Color(0xFF764BA2)],
      [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
    ];

    final colorIndex = item.name.length % gradients.length;
    final itemGradient = gradients[colorIndex];

    // Calculate progress based on spending wallet balance
    final progress = balance >= item.price
        ? 1.0
        : (balance / item.price).clamp(0.0, 1.0);
    final canAfford = balance >= item.price;

    return Container(
      margin: EdgeInsets.only(bottom: 20.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: itemGradient,
        ),
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: itemGradient[0].withOpacity(0.4),
            blurRadius: 20.r,
            offset: Offset(0, 10.h),
          ),
        ],
      ),
      child: Container(
        margin: EdgeInsets.all(3.w),
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Fun animated icon bubble
                _sparkleController != null
                    ? AnimatedBuilder(
                        animation: _sparkleController!,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: canAfford
                                ? 1.0 +
                                      (0.1 *
                                          (1 + _sparkleController!.value * 0.3))
                                : 1.0,
                            child: Container(
                              padding: EdgeInsets.all(14.w),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: itemGradient),
                                borderRadius: BorderRadius.circular(18.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: itemGradient[0].withOpacity(
                                      canAfford ? 0.5 : 0.3,
                                    ),
                                    blurRadius: 12.r,
                                    offset: Offset(0, 4.h),
                                  ),
                                ],
                              ),
                              child: Text(
                                _getItemEmoji(item.name),
                                style: TextStyle(fontSize: 28.sp),
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: itemGradient),
                          borderRadius: BorderRadius.circular(18.r),
                          boxShadow: [
                            BoxShadow(
                              color: itemGradient[0].withOpacity(
                                canAfford ? 0.5 : 0.3,
                              ),
                              blurRadius: 12.r,
                              offset: Offset(0, 4.h),
                            ),
                          ],
                        ),
                        child: Text(
                          _getItemEmoji(item.name),
                          style: TextStyle(fontSize: 28.sp),
                        ),
                      ),
                SizedBox(width: 14.w),
                // Item details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 19.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1C1243),
                                fontFamily: 'SF Pro Text',
                              ),
                            ),
                          ),
                          if (canAfford) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10.w,
                                vertical: 4.h,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF47C272),
                                    const Color(0xFF34A853),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🎉', style: TextStyle(fontSize: 12.sp)),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Can Buy!',
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontFamily: 'SF Pro Text',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.description.isNotEmpty) ...[
                        SizedBox(height: 4.h),
                        Text(
                          item.description,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: const Color(0xFF718096),
                            fontFamily: 'SF Pro Text',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 18.h),

            // Progress bar with fun design
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Progress',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF718096),
                        fontFamily: 'SF Pro Text',
                      ),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: itemGradient[0],
                        fontFamily: 'SF Pro Text',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        // Background
                        Container(
                          height: 10.h,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        // Progress
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          height: 10.h,
                          width: constraints.maxWidth * progress,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: itemGradient),
                            borderRadius: BorderRadius.circular(10.r),
                            boxShadow: [
                              BoxShadow(
                                color: itemGradient[0].withOpacity(0.4),
                                blurRadius: 8.r,
                                offset: Offset(0, 2.h),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Text(
                      'Spending Wallet: ',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: const Color(0xFF718096),
                        fontFamily: 'SF Pro Text',
                      ),
                    ),
                    Text(
                      '${balance.toStringAsFixed(2)} SAR',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF47C272),
                        fontFamily: 'SF Pro Text',
                      ),
                    ),
                    Text(
                      ' / ${item.price.toStringAsFixed(2)} SAR',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: const Color(0xFF718096),
                        fontFamily: 'SF Pro Text',
                      ),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: 16.h),

            // Bottom row with price and actions
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 10.h,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: itemGradient),
                    borderRadius: BorderRadius.circular(20.r),
                    boxShadow: [
                      BoxShadow(
                        color: itemGradient[0].withOpacity(0.3),
                        blurRadius: 8.r,
                        offset: Offset(0, 4.h),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sparkleController != null
                          ? AnimatedBuilder(
                              animation: _sparkleController!,
                              builder: (context, child) {
                                return Transform.rotate(
                                  angle:
                                      _sparkleController!.value * 2 * 3.14159,
                                  child: Text(
                                    '⭐',
                                    style: TextStyle(fontSize: 14.sp),
                                  ),
                                );
                              },
                            )
                          : Text('⭐', style: TextStyle(fontSize: 14.sp)),
                      SizedBox(width: 6.w),
                      Text(
                        "${item.price.toStringAsFixed(2)} SAR",
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                // Action buttons
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _showEditItemDialog(item),
                        icon: Icon(
                          Icons.edit_rounded,
                          color: const Color(0xFF643FDB),
                          size: 22.sp,
                        ),
                        padding: EdgeInsets.all(10.w),
                        constraints: BoxConstraints(),
                      ),
                      Container(
                        width: 1.5,
                        height: 24.h,
                        color: Colors.grey[300],
                      ),
                      IconButton(
                        onPressed: () => _showDeleteItemDialog(item),
                        icon: Icon(
                          Icons.delete_rounded,
                          color: const Color(0xFFFF6A5D),
                          size: 22.sp,
                        ),
                        padding: EdgeInsets.all(10.w),
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getItemEmoji(String itemName) {
    final name = itemName.toLowerCase();
    // Tech & Electronics
    if (name.contains('game') ||
        name.contains('play') ||
        name.contains('console') ||
        name.contains('nintendo') ||
        name.contains('xbox'))
      return '🎮';
    if (name.contains('phone') ||
        name.contains('iphone') ||
        name.contains('mobile'))
      return '📱';
    if (name.contains('laptop') ||
        name.contains('computer') ||
        name.contains('pc'))
      return '💻';
    if (name.contains('tablet') || name.contains('ipad')) return '📱';
    if (name.contains('camera')) return '📷';
    if (name.contains('music') ||
        name.contains('headphone') ||
        name.contains('earphone') ||
        name.contains('airpod'))
      return '🎧';
    if (name.contains('watch') || name.contains('smartwatch')) return '⌚';
    if (name.contains('drone')) return '🛸';
    if (name.contains('robot')) return '🤖';

    // Sports & Outdoors
    if (name.contains('bike') ||
        name.contains('cycle') ||
        name.contains('bicycle'))
      return '🚲';
    if (name.contains('ball') ||
        name.contains('football') ||
        name.contains('soccer'))
      return '⚽';
    if (name.contains('basketball')) return '🏀';
    if (name.contains('skate')) return '🛹';
    if (name.contains('swim') || name.contains('pool')) return '🏊';
    if (name.contains('tennis')) return '🎾';

    // Creative & Learning
    if (name.contains('book')) return '📚';
    if (name.contains('art') || name.contains('paint') || name.contains('draw'))
      return '🎨';
    if (name.contains('music') ||
        name.contains('guitar') ||
        name.contains('piano'))
      return '🎵';
    if (name.contains('lego') || name.contains('block')) return '🧱';
    if (name.contains('puzzle')) return '🧩';

    // Fashion & Accessories
    if (name.contains('shoe') ||
        name.contains('sneaker') ||
        name.contains('boot'))
      return '👟';
    if (name.contains('cloth') ||
        name.contains('shirt') ||
        name.contains('dress') ||
        name.contains('hoodie'))
      return '👕';
    if (name.contains('bag') || name.contains('backpack')) return '🎒';
    if (name.contains('hat') || name.contains('cap')) return '🧢';
    if (name.contains('glass') || name.contains('sunglass')) return '🕶️';

    // Toys & Fun
    if (name.contains('toy')) return '🧸';
    if (name.contains('doll')) return '🪆';
    if (name.contains('car') && !name.contains('card')) return '🚗';
    if (name.contains('train')) return '🚂';
    if (name.contains('plane')) return '✈️';

    // Animals & Pets
    if (name.contains('pet') ||
        name.contains('dog') ||
        name.contains('cat') ||
        name.contains('animal'))
      return '🐾';

    // Food & Treats
    if (name.contains('candy') || name.contains('sweet')) return '🍬';
    if (name.contains('ice cream')) return '🍦';
    if (name.contains('pizza')) return '🍕';

    // Special
    if (name.contains('star') ||
        name.contains('dream') ||
        name.contains('wish'))
      return '⭐';
    if (name.contains('rocket') || name.contains('space')) return '🚀';
    if (name.contains('magic') || name.contains('sparkle')) return '✨';
    if (name.contains('trophy') ||
        name.contains('prize') ||
        name.contains('reward'))
      return '🏆';

    return '🎁'; // Default gift emoji
  }

  void _showAddItemDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF643FDB), const Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text('💫', style: TextStyle(fontSize: 24.sp)),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                "Add to Wishlist",
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SF Pro Text',
                  color: const Color(0xFF1C1243),
                ),
              ),
            ),
          ],
        ),
        contentPadding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Item Name",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: "Price (SAR)",
                  prefixText: "SAR ",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: "Description (Optional)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: const Color(0xFFA29EB6),
                fontFamily: 'SF Pro Text',
                fontSize: 14.sp,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF643FDB), const Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF643FDB).withOpacity(0.3),
                  blurRadius: 8.r,
                  offset: Offset(0, 4.h),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    priceController.text.isNotEmpty) {
                  try {
                    final price = double.parse(priceController.text);
                    await WishlistService.addWishlistItem(
                      widget.parentId,
                      widget.childId,
                      nameController.text,
                      price,
                      descriptionController.text,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Text('🎉  '),
                            Expanded(
                              child: Text('Item added to your wishlist!'),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF47C272),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to add item: $e'),
                        backgroundColor: const Color(0xFFFF6A5D),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle, size: 20.sp),
                  SizedBox(width: 8.w),
                  Text(
                    "Add to Wishlist",
                    style: TextStyle(
                      fontFamily: 'SF Pro Text',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditItemDialog(WishlistItem item) {
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.price.toString());
    final descriptionController = TextEditingController(text: item.description);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          "Edit Item",
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Text',
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Item Name",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: "Price (SAR)",
                  prefixText: "SAR ",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: "Description (Optional)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: const Color(0xFFA29EB6),
                fontFamily: 'SF Pro Text',
                fontSize: 14.sp,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  priceController.text.isNotEmpty) {
                try {
                  final price = double.parse(priceController.text);
                  await WishlistService.updateWishlistItem(
                    widget.parentId,
                    widget.childId,
                    item.id,
                    nameController.text,
                    price,
                    descriptionController.text,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Item updated successfully!'),
                      backgroundColor: const Color(0xFF47C272),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update item: $e'),
                      backgroundColor: const Color(0xFFFF6A5D),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF643FDB),
              foregroundColor: Colors.white,
            ),
            child: Text(
              "Update",
              style: TextStyle(fontFamily: 'SF Pro Text', fontSize: 14.sp),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteItemDialog(WishlistItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          "Delete Item",
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Text',
          ),
        ),
        content: Text(
          "Are you sure you want to delete '${item.name}' from your wishlist?",
          style: TextStyle(fontSize: 14.sp, fontFamily: 'SF Pro Text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: const Color(0xFFA29EB6),
                fontFamily: 'SF Pro Text',
                fontSize: 14.sp,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await WishlistService.deleteWishlistItem(
                  widget.parentId,
                  widget.childId,
                  item.id,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Item deleted successfully!'),
                    backgroundColor: const Color(0xFF47C272),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete item: $e'),
                    backgroundColor: const Color(0xFFFF6A5D),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6A5D),
              foregroundColor: Colors.white,
            ),
            child: Text(
              "Delete",
              style: TextStyle(fontFamily: 'SF Pro Text', fontSize: 14.sp),
            ),
          ),
        ],
      ),
    );
  }

  void _onNavTap(BuildContext context, int index) {
    if (index == _navBarIndex) return;

    setState(() {
      _navBarIndex = index;
    });

    switch (index) {
      case 0:
        // Navigate to Homer
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                HomeScreen(parentId: widget.parentId, childId: widget.childId),
          ),
        );
        break;
      case 1:
        // Navigate to Tasks
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChildTaskViewScreen(
              parentId: widget.parentId,
              childId: widget.childId,
            ),
          ),
        );
        break;
      case 2:
        // Already on Wishlist
        break;
      case 3:
        // Navigate to Leaderboard
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leaderboard coming soon')),
        );
        break;
    }
  }
}
