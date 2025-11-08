// child_main_wrapper.dart
import 'package:flutter/material.dart';
import 'child/child_home_screen.dart';
import 'child/child_task_view_screen.dart';
import 'child/wishlist_screen.dart';
import 'child/leaderboard/leaderboard_screen.dart';
import '../../widgets/custom_bottom_nav.dart';
import 'services/notification_service.dart';

class ChildMainWrapper extends StatefulWidget {
  final String parentId;
  final String childId;
  const ChildMainWrapper({
    Key? key,
    required this.parentId,
    required this.childId,
  }) : super(key: key);

  @override
  State<ChildMainWrapper> createState() => _ChildMainWrapperState();
}

class _ChildMainWrapperState extends State<ChildMainWrapper> {
  int _currentIndex = 0;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('🎯 ===== ChildMainWrapper.initState START =====');
    // ignore: avoid_print
    print('🎯 parentId: ${widget.parentId}, childId: ${widget.childId}');

    // Initialize notifications for the child role (local + FCM + Firestore listener)
    // Use a microtask to ensure widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: avoid_print
      print('🎯 PostFrameCallback: Starting notification initialization...');
      _notificationService
          .initializeForChild(
            parentId: widget.parentId,
            childId: widget.childId,
          )
          .then((_) {
            // ignore: avoid_print
            print('🎯 Notification initialization completed');
          })
          .catchError((error, stackTrace) {
            // ignore: avoid_print
            print(
              '❌ ===== FAILED TO INITIALIZE NOTIFICATIONS IN WRAPPER =====',
            );
            // ignore: avoid_print
            print('❌ Error: $error');
            // ignore: avoid_print
            print('❌ Stack: $stackTrace');
          });
    });

    // ignore: avoid_print
    print('🎯 ===== ChildMainWrapper.initState END =====');
  }

  @override
  void dispose() {
    _notificationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build screens outside the list so they get correct props
    final home = HomeScreen(
      parentId: widget.parentId,
      childId: widget.childId,
      // showBottomNav: false, // Don't show bottom nav since wrapper handles it
    );
    final tasks = ChildTaskViewScreen(
      parentId: widget.parentId,
      childId: widget.childId,
      // showBottomNav: false, // Don't show bottom nav since wrapper handles it
    );
    final wishlist = WishlistScreen(
      parentId: widget.parentId,
      childId: widget.childId,
      // showBottomNav: false, // Don't show bottom nav since wrapper handles it
    );
    final leaderboard = LeaderboardScreen(
      parentId: widget.parentId,
      childId: widget.childId,
    );

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [home, tasks, wishlist, leaderboard],
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex:
            _currentIndex, // 0 = Home, 1 = Tasks, 2 = Wishlist, 3 = Leaderboard
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
      ),
    );
  }
}
