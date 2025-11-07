import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:toastification/toastification.dart';

import '../../models/wishlist_item.dart';
import '../../models/wallet.dart';
import '../services/wishlist_service.dart';
import '../services/firebase_service.dart';

class ChildWishlistDetailsScreen extends StatefulWidget {
  final String parentId;
  final String childId;
  final String childName;

  const ChildWishlistDetailsScreen({
    super.key,
    required this.parentId,
    required this.childId,
    required this.childName,
  });

  @override
  State<ChildWishlistDetailsScreen> createState() =>
      _ChildWishlistDetailsScreenState();
}

class _ChildWishlistDetailsScreenState extends State<ChildWishlistDetailsScreen>
    with SingleTickerProviderStateMixin {
  String _sortBy =
      'name'; // 'name', 'price_low', 'price_high', 'purchase_status'
  bool _sortAscending = true;
  String? _filterBy; // 'affordable', 'pending', 'purchased'
  Wallet? _wallet;
  bool _isLoadingWallet = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadWallet();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    try {
      final wallet = await FirebaseService.getChildWallet(
        widget.parentId,
        widget.childId,
      );
      setState(() {
        _wallet = wallet;
        _isLoadingWallet = false;
      });
    } catch (e) {
      setState(() => _isLoadingWallet = false);
    }
  }

  String _getItemEmoji(String itemName) {
    final name = itemName.toLowerCase();

    // Electronics & Tech
    if (name.contains('phone') ||
        name.contains('iphone') ||
        name.contains('android') ||
        name.contains('samsung'))
      return '📱';
    if (name.contains('tablet') || name.contains('ipad')) return '📱';
    if (name.contains('laptop') ||
        name.contains('computer') ||
        name.contains('macbook'))
      return '💻';
    if (name.contains('playstation') ||
        name.contains('ps5') ||
        name.contains('ps4') ||
        name.contains('xbox') ||
        name.contains('nintendo'))
      return '🎮';
    if (name.contains('headphone') ||
        name.contains('earphone') ||
        name.contains('airpod'))
      return '🎧';
    if (name.contains('watch') ||
        name.contains('smartwatch') ||
        name.contains('apple watch'))
      return '⌚';
    if (name.contains('camera')) return '📷';

    // Toys & Games
    if (name.contains('toy') ||
        name.contains('teddy') ||
        name.contains('bear') ||
        name.contains('doll'))
      return '🧸';
    if (name.contains('lego') || name.contains('block')) return '🧱';
    if (name.contains('board game') || name.contains('puzzle')) return '🧩';
    if (name.contains('bike') || name.contains('bicycle')) return '🚲';
    if (name.contains('skateboard')) return '🛹';

    // Fashion & Accessories
    if (name.contains('bag') ||
        name.contains('backpack') ||
        name.contains('purse'))
      return '👜';
    if (name.contains('shoes') ||
        name.contains('sneaker') ||
        name.contains('boot'))
      return '👟';
    if (name.contains('watch')) return '⌚';
    if (name.contains('jewelry') ||
        name.contains('necklace') ||
        name.contains('ring') ||
        name.contains('bracelet'))
      return '💍';
    if (name.contains('dress') ||
        name.contains('clothes') ||
        name.contains('shirt') ||
        name.contains('pants'))
      return '👕';

    // Books & Education
    if (name.contains('book') ||
        name.contains('novel') ||
        name.contains('comic'))
      return '📚';
    if (name.contains('notebook') || name.contains('journal')) return '📔';
    if (name.contains('pencil') ||
        name.contains('pen') ||
        name.contains('stationery'))
      return '✏️';

    // Food & Drink
    if (name.contains('pizza') ||
        name.contains('burger') ||
        name.contains('food'))
      return '🍕';
    if (name.contains('ice cream') ||
        name.contains('cake') ||
        name.contains('chocolate'))
      return '🍰';
    if (name.contains('juice') ||
        name.contains('drink') ||
        name.contains('soda'))
      return '🥤';

    // Sports & Activities
    if (name.contains('ball') ||
        name.contains('football') ||
        name.contains('basketball'))
      return '⚽';
    if (name.contains('swim') || name.contains('pool')) return '🏊';
    if (name.contains('bike') || name.contains('bicycle')) return '🚲';

    // Entertainment
    if (name.contains('movie') ||
        name.contains('film') ||
        name.contains('cinema'))
      return '🎬';
    if (name.contains('music') || name.contains('album')) return '🎵';
    if (name.contains('concert') || name.contains('ticket')) return '🎫';

    // Other
    if (name.contains('car') || name.contains('vehicle')) return '🚗';
    if (name.contains('pet') || name.contains('dog') || name.contains('cat'))
      return '🐾';
    if (name.contains('plant') || name.contains('flower')) return '🌱';
    if (name.contains('gift') || name.contains('present')) return '🎁';
    if (name.contains('money') ||
        name.contains('cash') ||
        name.contains('wallet'))
      return '💰';

    // Default emoji
    return '✨';
  }

  bool _isAffordable(WishlistItem item) {
    if (_wallet == null || _isLoadingWallet) return false;
    return _wallet!.spendingBalance >= item.price;
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20.r),
              topRight: Radius.circular(20.r),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Sort & Filter',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 24.h),
                // Sort Section
                Text(
                  'Sort by',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                SizedBox(height: 12.h),
                _buildSortOption('Name (A–Z)', 'name', setModalState),
                _buildSortOption(
                  'Price: Low → High',
                  'price_low',
                  setModalState,
                ),
                _buildSortOption(
                  'Price: High → Low',
                  'price_high',
                  setModalState,
                ),
                _buildSortOption(
                  'Purchase Status',
                  'purchase_status',
                  setModalState,
                ),
                SizedBox(height: 24.h),
                // Filter Section
                Text(
                  'Filter by Status',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                SizedBox(height: 12.h),
                _buildFilterOption(
                  '🟢 Affordable',
                  'affordable',
                  setModalState,
                ),
                _buildFilterOption('🟣 Pending', 'pending', setModalState),
                _buildFilterOption('🟦 Purchased', 'purchased', setModalState),
                SizedBox(height: 24.h),
                // Done Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(
    String label,
    String value,
    StateSetter setModalState,
  ) {
    final isSelected = _sortBy == value;
    return InkWell(
      onTap: () {
        setState(() {
          if (_sortBy == value && value == 'name') {
            // Toggle only for name sorting
            _sortAscending = !_sortAscending;
          } else {
            _sortBy = value;
            // Set default direction based on sort type
            if (value == 'price_low') {
              _sortAscending = true; // Ascending for low to high
            } else if (value == 'price_high') {
              _sortAscending = false; // Descending for high to low
            } else {
              _sortAscending = true; // Default ascending
            }
          }
        });
        // Update modal state immediately for instant UI feedback
        setModalState(() {});
        // Don't close dialog - let users select both sort and filter
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
        margin: EdgeInsets.only(bottom: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7C3AED).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
            if (isSelected && value == 'name')
              Icon(
                _sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: const Color(0xFF7C3AED),
                size: 20.sp,
              ),
            if (isSelected && value == 'price_low')
              Icon(
                Icons.arrow_upward_rounded,
                color: const Color(0xFF7C3AED),
                size: 20.sp,
              ),
            if (isSelected && value == 'price_high')
              Icon(
                Icons.arrow_downward_rounded,
                color: const Color(0xFF7C3AED),
                size: 20.sp,
              ),
            if (isSelected && value == 'purchase_status')
              Icon(
                _sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: const Color(0xFF7C3AED),
                size: 20.sp,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(
    String label,
    String value,
    StateSetter setModalState,
  ) {
    final isSelected = _filterBy == value;
    return InkWell(
      onTap: () {
        setState(() {
          // Toggle filter: if already selected, deselect it
          _filterBy = isSelected ? null : value;
        });
        // Update modal state immediately for instant UI feedback
        setModalState(() {});
        // Don't close dialog - let users select both sort and filter
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
        margin: EdgeInsets.only(bottom: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7C3AED).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: const Color(0xFF7C3AED),
                size: 20.sp,
              ),
          ],
        ),
      ),
    );
  }

  List<WishlistItem> _sortItems(List<WishlistItem> items) {
    // First apply filter
    List<WishlistItem> filtered = List<WishlistItem>.from(items);

    if (_filterBy != null) {
      filtered = filtered.where((item) {
        switch (_filterBy) {
          case 'affordable':
            return _isAffordable(item) && !item.isPurchased;
          case 'pending':
            return !_isAffordable(item) && !item.isPurchased;
          case 'purchased':
            return item.isPurchased;
          default:
            return true;
        }
      }).toList();
    }

    // Then apply sorting
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortBy) {
        case 'name':
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return _sortAscending ? comparison : -comparison;
        case 'price_low':
          // Always ascending for low to high
          return a.price.compareTo(b.price);
        case 'price_high':
          // Always descending for high to low
          return b.price.compareTo(a.price);
        case 'purchase_status':
          // Sort by purchased status
          comparison = (a.isPurchased ? 1 : 0).compareTo(b.isPurchased ? 1 : 0);
          return _sortAscending ? comparison : -comparison;
        default:
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return _sortAscending ? comparison : -comparison;
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.childName,
          style: TextStyle(
            color: const Color(0xFF1E293B),
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: const Color(0xFF1E293B),
            size: 20.sp,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.sort_rounded,
              color: const Color(0xFF1E293B),
              size: 24.sp,
            ),
            onPressed: _showSortDialog,
          ),
        ],
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
      body: StreamBuilder<List<WishlistItem>>(
        stream: WishlistService.getWishlistItems(
          widget.parentId,
          widget.childId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
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
                    'Loading wishlist items...',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            );
          }

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
                    'Error loading wishlist',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    snapshot.error.toString(),
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: const Color(0xFF94A3B8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final items = snapshot.data ?? [];
          final sortedItems = _sortItems(items);

          if (items.isEmpty) {
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
                      Icons.favorite_border_rounded,
                      size: 48.sp,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'No wishlist items yet',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Items will appear here when added',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            );
          }

          // Responsive Grid of Wishlist Items
          return LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = constraints.maxWidth;
              final isTablet = screenWidth >= 600;
              final crossAxisCount = isTablet ? 3 : 2;

              return GridView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.70,
                  crossAxisSpacing: 12.w,
                  mainAxisSpacing: 12.h,
                ),
                itemCount: sortedItems.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () =>
                        _showItemProgressModal(sortedItems[index], items),
                    child: _buildWishlistItemCard(sortedItems[index]),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildWishlistItemCard(WishlistItem item) {
    final emoji = _getItemEmoji(item.name);
    final isAffordable = _isAffordable(item);
    final isPurchased = item.isPurchased;

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isPurchased
            ? const Color(
                0xFFF0F9FF,
              ) // Light blue background for purchased items
            : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isPurchased
              ? const Color(0xFF3B82F6).withOpacity(
                  0.3,
                ) // Light blue border for purchased
              : const Color(0xFFE2E8F0),
          width: isPurchased ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPurchased
                ? const Color(0xFF3B82F6).withOpacity(
                    0.15,
                  ) // Light blue shadow for purchased
                : Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji Display Area with Gradient Bubble
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPurchased
                      ? [
                          const Color(0xFF3B82F6).withOpacity(
                            0.15,
                          ), // Light blue gradient for purchased
                          const Color(0xFF60A5FA).withOpacity(0.1),
                        ]
                      : isAffordable
                      ? [
                          const Color(0xFF643FDB).withOpacity(0.15),
                          const Color(0xFF8B5CF6).withOpacity(0.1),
                        ]
                      : [const Color(0xFFF1F5F9), const Color(0xFFF8FAFC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.r),
                  topRight: Radius.circular(16.r),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Center emoji bubble
                  Center(
                    child: _buildEmojiBubble(emoji, isAffordable, isPurchased),
                  ),
                  // Sparkle effect for affordable items (not for purchased)
                  if (isAffordable && !isPurchased)
                    ...List.generate(4, (index) {
                      return _buildSparkleEffect(index);
                    }),
                  // Purchased icon overlay (🛍️)
                  if (isPurchased)
                    Positioned(
                      top: 8.h,
                      right: 8.w,
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF3B82F6,
                          ), // Light blue for purchased
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Text('🛍️', style: TextStyle(fontSize: 14.sp)),
                      ),
                    ),
                  // Purchased ribbon/badge in top-left corner
                  if (isPurchased)
                    Positioned(
                      top: -4.h,
                      left: 8.w,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF3B82F6),
                              const Color(0xFF60A5FA),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🛍️', style: TextStyle(fontSize: 10.sp)),
                            SizedBox(width: 4.w),
                            Text(
                              'Purchased',
                              style: TextStyle(
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Item Details
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Item Name and Description Section
                  Flexible(
                    flex: 1,
                    fit: FlexFit.loose,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Item Name with Emoji prefix
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 6.w),
                              child: Text(
                                emoji,
                                style: TextStyle(fontSize: 16.sp),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E293B),
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                        if (item.description.isNotEmpty) ...[
                          SizedBox(height: 4.h),
                          Flexible(
                            child: Text(
                              item.description,
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Price and Badge Row - Fixed at bottom
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Price - Use FittedBox to ensure it scales properly
                        Flexible(
                          flex: 1,
                          fit: FlexFit.loose,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '\﷼ ${item.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF7C3AED),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 6.w),
                        // Badge - Maintain its size
                        Flexible(
                          flex: 0,
                          fit: FlexFit.loose,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: isPurchased
                                  ? const Color(0xFF3B82F6).withOpacity(
                                      0.1,
                                    ) // Light blue for purchased
                                  : isAffordable
                                  ? const Color(0xFF7C3AED).withOpacity(0.1)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              isPurchased
                                  ? 'Purchased'
                                  : isAffordable
                                  ? 'Affordable'
                                  : 'Pending',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w600,
                                color: isPurchased
                                    ? const Color(
                                        0xFF3B82F6,
                                      ) // Light blue color for purchased
                                    : isAffordable
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Small spacer to prevent overflow
                  SizedBox(height: 1.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiBubble(String emoji, bool isAffordable, bool isPurchased) {
    final animation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: isAffordable && !isPurchased ? Curves.easeInOut : Curves.linear,
      ),
    );

    Widget emojiWidget = Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPurchased
              ? [
                  const Color(
                    0xFF3B82F6,
                  ).withOpacity(0.25), // Light blue gradient for purchased
                  const Color(0xFF60A5FA).withOpacity(0.15),
                ]
              : isAffordable
              ? [
                  const Color(0xFF643FDB).withOpacity(0.3),
                  const Color(0xFF8B5CF6).withOpacity(0.2),
                ]
              : [Colors.white.withOpacity(0.8), Colors.white.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isPurchased
                ? const Color(0xFF3B82F6).withOpacity(
                    0.25,
                  ) // Subtle blue glow for purchased
                : isAffordable && !isPurchased
                ? const Color(0xFF643FDB).withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 12,
            spreadRadius: isPurchased
                ? 1 // Subtle static glow for purchased
                : isAffordable && !isPurchased
                ? 2
                : 0,
          ),
        ],
      ),
      child: Text(emoji, style: TextStyle(fontSize: 40.sp)),
    );

    // Only animate if affordable and not purchased
    if (isAffordable && !isPurchased) {
      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Transform.scale(scale: animation.value, child: emojiWidget);
        },
      );
    }

    return emojiWidget;
  }

  Widget _buildSparkleEffect(int index) {
    final delays = [0.0, 0.5, 1.0, 1.5];
    final delayedAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          (delays[index] / 2).clamp(0.0, 1.0),
          ((delays[index] + 1) / 2).clamp(0.0, 1.0),
          curve: Curves.easeInOut,
        ),
      ),
    );

    Widget sparkle;
    switch (index) {
      case 0:
        sparkle = Positioned(
          left: 12.w,
          top: 12.h,
          child: _buildSparkleWidget(delayedAnimation),
        );
        break;
      case 1:
        sparkle = Positioned(
          right: 12.w,
          top: 12.h,
          child: _buildSparkleWidget(delayedAnimation),
        );
        break;
      case 2:
        sparkle = Positioned(
          left: 12.w,
          bottom: 12.h,
          child: _buildSparkleWidget(delayedAnimation),
        );
        break;
      case 3:
        sparkle = Positioned(
          right: 12.w,
          bottom: 12.h,
          child: _buildSparkleWidget(delayedAnimation),
        );
        break;
      default:
        sparkle = Positioned(
          left: 12.w,
          top: 12.h,
          child: _buildSparkleWidget(delayedAnimation),
        );
    }
    return sparkle;
  }

  Widget _buildSparkleWidget(Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: (animation.value * 0.8).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.5 + (animation.value * 1.0),
            child: Container(
              width: 8.w,
              height: 8.w,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.8),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePurchaseItem(WishlistItem item) async {
    try {
      await WishlistService.markWishlistItemAsPurchased(
        widget.parentId,
        widget.childId,
        item.id,
      );

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: const Text('✅ This item has been marked as purchased.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
        Navigator.of(context).pop(); // Close the modal
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.fillColored,
          title: Text('Error: ${e.toString()}'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  void _showPendingToast() {
    toastification.show(
      context: context,
      type: ToastificationType.warning,
      style: ToastificationStyle.fillColored,
      title: const Text(
        '⚠️ You can only purchase this item once it\'s affordable.',
      ),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  void _showItemProgressModal(WishlistItem item, List<WishlistItem> allItems) {
    final emoji = _getItemEmoji(item.name);
    final progressPercentage =
        (_wallet?.spendingBalance ?? 0.0) / item.price * 100;
    final canAfford = progressPercentage >= 100;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            // Item Header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF643FDB).withOpacity(0.2),
                        const Color(0xFF8B5CF6).withOpacity(0.15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: TextStyle(fontSize: 32.sp)),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '\﷼ ${item.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF643FDB),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.h),
            // Progress Section
            if (item.isPurchased) ...[
              // Purchased Items Section
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        shape: BoxShape.circle,
                      ),
                      child: Text('🛍️', style: TextStyle(fontSize: 20.sp)),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This item has been purchased by the child.',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            'The child has successfully bought this item.',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Wallet Balance',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    '\﷼ ${(_wallet?.spendingBalance ?? 0.0).toStringAsFixed(2)} / \﷼ ${item.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: LinearProgressIndicator(
                  value: progressPercentage.clamp(0.0, 1.0),
                  minHeight: 10.h,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    canAfford
                        ? const Color(0xFF10B981)
                        : const Color(0xFF643FDB),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${progressPercentage.clamp(0.0, 100.0).toStringAsFixed(0)}% Complete',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: canAfford
                          ? const Color(0xFF10B981).withOpacity(0.1)
                          : const Color(0xFF643FDB).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      canAfford ? 'Affordable!' : 'In Progress',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: canAfford
                            ? const Color(0xFF10B981)
                            : const Color(0xFF643FDB),
                      ),
                    ),
                  ),
                ],
              ),
              // Purchase It Button (only show if not purchased)
              if (!item.isPurchased) ...[
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canAfford
                        ? () => _handlePurchaseItem(item)
                        : () => _showPendingToast(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: canAfford ? 2 : 0,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_rounded, size: 20.sp),
                        SizedBox(width: 8.w),
                        Text(
                          'Purchase It',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            SizedBox(height: 24.h),
            if (item.description.isNotEmpty) ...[
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                item.description,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              SizedBox(height: 24.h),
            ],
            // Close Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF643FDB),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
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
