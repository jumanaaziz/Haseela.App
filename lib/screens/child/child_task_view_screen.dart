import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '/models/child.dart';
import '/models/task.dart';
import '/models/wallet.dart';
import '../services/haseela_service.dart';
import '../../widgets/custom_bottom_nav.dart'; // adjust the path if it's in another folder
import 'child_home_screen.dart';
import 'wishlist_screen.dart';

class ChildTaskViewScreen extends StatefulWidget {
  final String parentId;
  final String childId;

  const ChildTaskViewScreen({
    Key? key,
    required this.parentId,
    required this.childId,
  }) : super(key: key);

  @override
  State<ChildTaskViewScreen> createState() => _ChildTaskViewScreenState();
}

class _ChildTaskViewScreenState extends State<ChildTaskViewScreen> {
  CollectionReference<Map<String, dynamic>> _tasksRef() {
    return FirebaseFirestore.instance
        .collection('Parents')
        .doc(_currentParentId)
        .collection('Children')
        .doc(_currentChildId)
        .collection('Tasks');
  }

  int _navBarIndex =
      1; // For bottom navigation (0=Home, 1=Tasks, 2=Wishlist, 3=Leaderboard)
  int _taskTabIndex = 0; // For internal task tabs (0=New, 1=Pending, 2=Done)
  final HaseelaService _haseelaService = HaseelaService();
  final ImagePicker _imagePicker = ImagePicker();

  late String _currentParentId;
  late String _currentChildId;

  Child? _currentChild;

  // Image upload state
  Map<String, bool> _uploadingImages = {}; // taskId -> isUploading
  Map<String, String?> _selectedImages = {}; // taskId -> imagePath

  @override
  void initState() {
    super.initState();
    _currentParentId = widget.parentId;
    _currentChildId = widget.childId;
    _loadChildProfile();
  }

  void _onNavTap(BuildContext context, int index) {
    if (index == _navBarIndex) return; // avoid unnecessary rebuild

    setState(() {
      _navBarIndex = index;
    });

    switch (index) {
      case 0:
        // ✅ Go back to Child Home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                HomeScreen(parentId: widget.parentId, childId: widget.childId),
          ),
        );
        break;
      case 1:
        // Already on Tasks → do nothing
        break;
      case 2:
        // ✅ Navigate to Wishlist
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WishlistScreen(
              parentId: widget.parentId,
              childId: widget.childId,
            ),
          ),
        );
        break;
      case 3:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leaderboard coming soon')),
        );
        break;
    }
  }

  void _loadChildProfile() async {
    try {
      print(
        '🔍 Attempting to load child: $_currentChildId for parent: $_currentParentId',
      );
      // First, try to get the child with the current ID
      final child = await _haseelaService.getChild(
        _currentParentId,
        _currentChildId,
      );

      if (child != null) {
        print(
          '✅ Successfully loaded child: ${child.firstName} ${child.lastName}',
        );
        setState(() {
          _currentChild = child;
        });
      } else {
        print(
          '❌ Child $_currentChildId not found, discovering available children...',
        );
        // If child not found, try to discover available children
        _discoverAvailableChild();
      }
    } catch (e) {
      print('❌ Error loading child profile: $e');
      // Try to discover available child on error
      _discoverAvailableChild();
    }
  }

  void _discoverAvailableChild() async {
    try {
      print('=== DISCOVERING CHILDREN FOR PARENT: $_currentParentId ===');

      // Get all children for the parent
      final children = await _haseelaService.getAllChildren(_currentParentId);

      if (children.isNotEmpty) {
        print('Found ${children.length} children:');
        for (var child in children) {
          print('- ${child.firstName} ${child.lastName} (ID: ${child.id})');
        }

        // Look for Sara specifically first
        try {
          final sara = children.firstWhere(
            (child) => child.firstName.toLowerCase().contains('sara'),
          );

          print(
            '✅ FOUND SARA: ${sara.firstName} ${sara.lastName} with ID: ${sara.id}',
          );
          setState(() {
            _currentChildId = sara.id;
            _currentChild = sara;
          });
          return;
        } catch (e) {
          print('❌ Sara not found in the children list');
          print(
            'Available children: ${children.map((c) => '${c.firstName} ${c.lastName}').toList()}',
          );

          // If Sara not found, use the first available child
          print('⚠️ Using first available child instead');
          final firstChild = children.first;
          setState(() {
            _currentChildId = firstChild.id;
            _currentChild = firstChild;
          });
          return;
        }
      } else {
        print('❌ No children found for parent $_currentParentId');
      }

      // Fallback: try common child IDs that might be Sara
      print('=== TRYING FALLBACK CHILD IDs ===');
      List<String> possibleChildIds = [
        'child001', // Sara's tasks are stored here
        'Child001',
        'sara',
        'Sara',
        'SARA',
        'child_sara',
        'sara001',
        'child002',
      ];

      for (String childId in possibleChildIds) {
        print('Trying child ID: $childId');
        try {
          final child = await _haseelaService.getChild(
            _currentParentId,
            childId,
          );
          if (child != null) {
            print(
              '✅ Found child: ${child.firstName} ${child.lastName} with ID: $childId',
            );
            setState(() {
              _currentChildId = childId;
              _currentChild = child;
            });
            return;
          }
        } catch (e) {
          print('Error trying child ID $childId: $e');
        }
      }

      print('❌ No child found with any of the tried IDs');
      // Create a fallback child to prevent crashes
      _createFallbackChild();
    } catch (e) {
      print('Error discovering child: $e');
      // Create a fallback child to prevent crashes
      _createFallbackChild();
    }
  }

  void _createFallbackChild() {
    print('🔧 Creating fallback child to prevent app crashes');
    setState(() {
      _currentChild = Child(
        id: 'fallback',
        firstName: 'Child',
        lastName: 'User',
        email: 'child@example.com',
        avatar: '',
        qr: '',
        parent: FirebaseFirestore.instance
            .collection('Parents')
            .doc('parent001'),
        level: 1, // ✅ Added this line to satisfy required parameter
      );
      _currentChildId = 'fallback';
    });
  }

  @override
  Widget build(BuildContext context) {
    print('=== BUILDING ChildTaskViewScreen ===');
    print(
      'Current child: ${_currentChild?.firstName ?? 'None'} (ID: $_currentChildId)',
    );

    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      body: StreamBuilder<List<Task>>(
        stream: _haseelaService.getTasksForChild(
          _currentParentId,
          _currentChildId,
        ),
        builder: (context, snapshot) {
          print(
            'StreamBuilder - Connection State: ${snapshot.connectionState}',
          );
          print('StreamBuilder - Has Error: ${snapshot.hasError}');
          print('StreamBuilder - Has Data: ${snapshot.hasData}');
          print('StreamBuilder - Data: ${snapshot.data}');

          if (snapshot.hasError) {
            final errorMsg = snapshot.error.toString();
            if (errorMsg.contains('unavailable') ||
                errorMsg.contains('connection') ||
                errorMsg.contains('timeout')) {
              return _buildOfflineState();
            }
            return _buildErrorState(errorMsg);
          }

          if (snapshot.connectionState == ConnectionState.waiting ||
              snapshot.data == null) {
            return _buildLoadingState();
          }

          final allTasks = snapshot.data!;
          if (allTasks.isEmpty) {
            return _buildEmptyState(
              'No tasks found',
              'Once tasks are assigned, they will appear here',
              Icons.assignment,
            );
          }

          final newTasks = allTasks
              .where((t) => t.status.toLowerCase() == 'new')
              .toList();
          final pendingTasks = allTasks
              .where((t) => t.status.toLowerCase() == 'pending')
              .toList();
          final doneTasks = allTasks
              .where(
                (t) =>
                    t.status.toLowerCase() == 'done' ||
                    t.status.toLowerCase() == 'rejected',
              )
              //.where((t) => t.status.toLowerCase() == 'done')
              .toList();

          return Column(
            children: [
              StreamBuilder<Wallet?>(
                stream: _haseelaService.getWalletForChild(
                  _currentParentId,
                  _currentChildId,
                ),
                builder: (context, walletSnapshot) {
                  final wallet = walletSnapshot.data;
                  return _buildHeader(allTasks, doneTasks, wallet, doneTasks);
                },
              ),
              _buildToggleButtons(),
              Expanded(
                child: _buildCurrentTabContent(
                  newTasks,
                  pendingTasks,
                  doneTasks,
                ),
              ),
            ],
          );
        },
      ),
      // Bottom navigation is handled by ChildMainWrapper
    );
  }

  // ==========================
  // 🧩 Helper UI methods below
  // ==========================
  Widget _buildOfflineState() {
    return Column(
      children: [
        _buildHeader([], [], null, []),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'You are offline',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Please check your internet connection\nand try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String error) {
    return Column(
      children: [
        _buildHeader([], [], null, []),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Error Loading Tasks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Debug Info:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Parent ID: $_currentParentId',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          'Child ID: $_currentChildId',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Error: $error',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: Text('Retry'),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Make sure your Firebase project is configured\nand the documents exist in Firestore',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF333333)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        _buildHeader([], [], null, []),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF643FDB)),
                SizedBox(height: 16),
                Text('Loading your tasks...'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    List<Task> allTasks,
    List<Task> completedTasks,
    Wallet? wallet,
    List<Task> completedTasksForEarning,
  ) {
    final totalTasks = allTasks.length;
    /* final totalEarned = completedTasksForEarning.fold(
      0.0,
      (sum, task) => sum + task.allowance,
    );*/
    // Only count approved tasks (status = 'done'), NOT rejected tasks
    // final totalEarned = completedTasksForEarning
    final approvedTasks = completedTasksForEarning
        .where((task) => task.status.toLowerCase() == 'done')
        //.fold(0.0, (sum, task) => sum + task.allowance);
        .toList();
    final totalEarned = approvedTasks.fold(
      0.0,
      (sum, task) => sum + task.allowance,
    );
    final childName = _currentChild?.firstName ?? 'Nouf';

    return Container(
      height: MediaQuery.of(context).size.height * 0.35,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF80D8A0), // Light green
            Color(0xFFA080D8), // Light purple/lavender
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile and notification
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: MediaQuery.of(context).size.width * 0.05,
                        backgroundImage:
                            _currentChild?.avatar.isNotEmpty == true
                            ? NetworkImage(_currentChild!.avatar)
                            : null,
                        backgroundColor: Colors.white,
                        child: _currentChild?.avatar.isEmpty != false
                            ? Icon(
                                Icons.person,
                                color: Colors.grey[400],
                                size: MediaQuery.of(context).size.width * 0.05,
                              )
                            : null,
                      ),
                      SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Tasks, $childName',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.05,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Let’s make today count!",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.035,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.all(
                      MediaQuery.of(context).size.width * 0.02,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(
                        MediaQuery.of(context).size.width * 0.03,
                      ),
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                      size: MediaQuery.of(context).size.width * 0.06,
                    ),
                  ),
                ],
              ),

              SizedBox(height: MediaQuery.of(context).size.height * 0.04),

              // Tasks and Earnings summary
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          //'${completedTasks.length}/$totalTasks Tasks',
                          '${approvedTasks.length}/$totalTasks Tasks',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width * 0.05,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.005,
                        ),
                        Text(
                          'Completed this week',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: MediaQuery.of(context).size.width * 0.035,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '🏆',
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.04,
                              ),
                            ),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.01,
                            ),
                            Flexible(
                              child: Text(
                                '${totalEarned.toStringAsFixed(0)} ﷼ Earned',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize:
                                      MediaQuery.of(context).size.width * 0.04,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButtons() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
        vertical: MediaQuery.of(context).size.height * 0.02,
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleButton(
              'New',
              Icons.assignment,
              _taskTabIndex == 0,
              () => setState(() => _taskTabIndex = 0),
            ),
          ),
          SizedBox(width: MediaQuery.of(context).size.width * 0.015),
          Expanded(
            child: _buildToggleButton(
              'Pending',
              Icons.schedule,
              _taskTabIndex == 1,
              () => setState(() => _taskTabIndex = 1),
            ),
          ),
          SizedBox(width: MediaQuery.of(context).size.width * 0.015),
          Expanded(
            child: _buildToggleButton(
              'Done',
              Icons.check_circle,
              _taskTabIndex == 2,
              () => setState(() => _taskTabIndex = 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTabContent(
    List<Task> newTasks,
    List<Task> pendingTasks,
    List<Task> doneTasks,
  ) {
    switch (_taskTabIndex) {
      case 0:
        return _buildNewTasks(newTasks);
      case 1:
        return _buildPendingTasks(pendingTasks);
      case 2:
        return _buildCompletedTasks(doneTasks);
      default:
        return _buildNewTasks(newTasks);
    }
  }

  Widget _buildToggleButton(
    String text,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.012,
          horizontal: MediaQuery.of(context).size.width * 0.015,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF643FDB) : Colors.grey[100],
          borderRadius: BorderRadius.circular(
            MediaQuery.of(context).size.width * 0.015,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: MediaQuery.of(context).size.width * 0.04,
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.002),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: MediaQuery.of(context).size.width * 0.028,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewTasks(List<Task> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        'No new tasks right now!',
        'Check back later for new tasks',
        Icons.assignment,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
      ),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        return _buildTaskCard(tasks[index]);
      },
    );
  }

  Widget _buildPendingTasks(List<Task> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        'No tasks waiting for approval!',
        'Complete some tasks to see them here',
        Icons.schedule,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
      ),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        return _buildPendingTaskCard(tasks[index]);
      },
    );
  }

  Widget _buildCompletedTasks(List<Task> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        'No completed tasks yet!',
        'Complete some tasks to see them here',
        Icons.check_circle,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
      ),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        return _buildCompletedTaskCard(tasks[index]);
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: MediaQuery.of(context).size.width * 0.2,
              color: Colors.grey[300],
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
            Text(
              title,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.045,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.035,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    final isChallenge = task.isChallenge;
    final cardColor = isChallenge
        ? const Color(0xFFFFD700).withOpacity(0.1) // Light gold background
        : Colors.white;
    final borderColor = isChallenge
        ? Colors
              .amber
              .shade600 // Gold border
        : Colors.transparent;

    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height * 0.02,
      ),
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.05),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(
          MediaQuery.of(context).size.width * 0.04,
        ),
        border: Border.all(color: borderColor, width: isChallenge ? 2.0 : 0.0),
        boxShadow: [
          BoxShadow(
            color: isChallenge
                ? Colors.amber.withOpacity(0.2) // Gold shadow
                : Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Challenge badge
          if (isChallenge)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade600, Colors.amber.shade800],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Challenge Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

          // Header with category icon and title
          Row(
            children: [
              if (task.categoryIcon != null) ...[
                Container(
                  padding: EdgeInsets.all(
                    MediaQuery.of(context).size.width * 0.02,
                  ),
                  decoration: BoxDecoration(
                    color:
                        task.categoryColor?.withOpacity(0.1) ??
                        Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      MediaQuery.of(context).size.width * 0.02,
                    ),
                  ),
                  child: Icon(
                    task.categoryIcon!,
                    color: task.categoryColor ?? Colors.grey,
                    size: MediaQuery.of(context).size.width * 0.05,
                  ),
                ),
                SizedBox(width: MediaQuery.of(context).size.width * 0.03),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.taskName,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.045,
                        fontWeight: FontWeight.w600,
                        color: isChallenge
                            ? Colors.amber.shade900
                            : Color(0xFF333333),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _getPriorityInfo(task.priority)['icon'],
                          size: 14,
                          color: _getPriorityInfo(task.priority)['color'],
                        ),
                        SizedBox(width: 4),
                        Text(
                          _getPriorityInfo(task.priority)['text'],
                          style: TextStyle(
                            fontSize: 12,
                            color: _getPriorityInfo(task.priority)['color'],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: MediaQuery.of(context).size.height * 0.02),

          // Reward and Due Date
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.02,
                  vertical: MediaQuery.of(context).size.height * 0.005,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(
                    MediaQuery.of(context).size.width * 0.015,
                  ),
                ),
                child: Text(
                  '💰 ${task.allowance.toStringAsFixed(0)} ﷼',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                    fontSize: MediaQuery.of(context).size.width * 0.035,
                  ),
                ),
              ),
              if (task.dueDate != null) ...[
                SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                Icon(
                  Icons.schedule,
                  size: MediaQuery.of(context).size.width * 0.04,
                  color: Colors.grey[500],
                ),
                SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                Text(
                  _formatDueDate(task.dueDate),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: MediaQuery.of(context).size.width * 0.035,
                  ),
                ),
              ],
            ],
          ),

          SizedBox(height: MediaQuery.of(context).size.height * 0.025),

          // Image preview (if selected)
          if (_selectedImages[task.id] != null) ...[
            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_selectedImages[task.id]!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: Icon(Icons.error, color: Colors.red),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
          ],

          // Task completion buttons
          _isTaskOverdue(task)
              ? // Single button for overdue tasks
              ElevatedButton.icon(
                  onPressed: null,
                  icon: Icon(
                    Icons.error_outline,
                    size: MediaQuery.of(context).size.width * 0.045,
                  ),
                  label: Text(
                    'Task Overdue',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.5),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: MediaQuery.of(context).size.height * 0.02,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        MediaQuery.of(context).size.width * 0.03,
                      ),
                    ),
                    elevation: 0,
                    minimumSize: Size(double.infinity, 0),
                  ),
                )
              : // Two buttons for non-overdue tasks
              Row(
                  children: [
                    // Upload photo button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _uploadingImages[task.id] == true
                            ? null
                            : () {
                                _pickImageFromGallery(task);
                              },
                        icon: _uploadingImages[task.id] == true
                            ? SizedBox(
                                width: MediaQuery.of(context).size.width * 0.045,
                                height: MediaQuery.of(context).size.width * 0.045,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.photo_library,
                                size: MediaQuery.of(context).size.width * 0.045,
                              ),
                        label: Text(
                          _uploadingImages[task.id] == true
                              ? 'Uploading...'
                              : 'Upload Photo',
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.04,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _uploadingImages[task.id] == true
                              ? Color(0xFF643FDB).withOpacity(0.5)
                              : Color(0xFF643FDB).withOpacity(0.7),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: MediaQuery.of(context).size.height * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              MediaQuery.of(context).size.width * 0.03,
                            ),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    SizedBox(width: 12),

                    // Complete task button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _uploadingImages[task.id] == true
                            ? null
                            : () {
                                _completeTaskWithoutPhoto(task);
                              },
                        icon: Icon(
                          Icons.check_circle_outline,
                          size: MediaQuery.of(context).size.width * 0.045,
                        ),
                        label: Text(
                          'Complete Task',
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.038,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _uploadingImages[task.id] == true
                              ? Color(0xFF47C272).withOpacity(0.5)
                              : Color(0xFF47C272),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: MediaQuery.of(context).size.height * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              MediaQuery.of(context).size.width * 0.03,
                            ),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildPendingTaskCard(Task task) {
    final isChallenge = task.isChallenge;
    final cardColor = isChallenge
        ? const Color(0xFFFFD700).withOpacity(0.1)
        : Colors.white;
    final borderColor = isChallenge
        ? Colors.amber.shade600
        : Colors.transparent;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isChallenge ? 2.0 : 0.0),
        boxShadow: [
          BoxShadow(
            color: isChallenge
                ? Colors.amber.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Challenge badge
          if (isChallenge)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade600, Colors.amber.shade800],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Challenge Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.schedule, color: Colors.orange, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.taskName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isChallenge
                            ? Colors.amber.shade900
                            : Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _getPriorityInfo(task.priority)['icon'],
                          size: 12,
                          color: _getPriorityInfo(task.priority)['color'],
                        ),
                        SizedBox(width: 4),
                        Text(
                          _getPriorityInfo(task.priority)['text'],
                          style: TextStyle(
                            fontSize: 12,
                            color: _getPriorityInfo(task.priority)['color'],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Waiting for parent approval • +${task.allowance.toStringAsFixed(0)} ﷼',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_getTaskImage(task) != null) ...[
                SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showImageDialog(_getTaskImage(task)!),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildTaskImage(_getTaskImage(task)!),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTaskCard(Task task) {
    // Determine status-based colors, icons, and messages
    final bool isDone = task.status.toLowerCase() == 'done';
    final bool isRejected = task.status.toLowerCase() == 'rejected';
    final Color statusColor = isDone
        ? Colors.green
        : (isRejected ? Colors.red : Colors.grey);
    final IconData statusIcon = isDone
        ? Icons.check_circle
        : (isRejected ? Icons.cancel : Icons.help_outline);
    final String statusMessage = isDone
        ? 'Approved by parent • +${task.allowance.toStringAsFixed(0)} ﷼'
        : (isRejected ? 'Rejected by parent' : 'Unknown status');
    final Color cardColor = Colors.white;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: task.isChallenge
                ? Colors.amber.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Challenge badge
          if (task.isChallenge)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade600, Colors.amber.shade800],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Challenge Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, color: statusColor, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.taskName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _getPriorityInfo(task.priority)['icon'],
                          size: 12,
                          color: _getPriorityInfo(task.priority)['color'],
                        ),
                        SizedBox(width: 4),
                        Text(
                          _getPriorityInfo(task.priority)['text'],
                          style: TextStyle(
                            fontSize: 12,
                            color: _getPriorityInfo(task.priority)['color'],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: 14,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_getTaskImage(task) != null) ...[
                SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showImageDialog(_getTaskImage(task)!),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildTaskImage(_getTaskImage(task)!),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDueDate(DateTime? dueDate) {
    if (dueDate == null) return '';

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime taskDate = DateTime(dueDate.year, dueDate.month, dueDate.day);

    int difference = taskDate.difference(today).inDays;

    if (difference == 0) {
      return 'Due Today';
    } else if (difference == 1) {
      return 'Due Tomorrow';
    } else if (difference > 1) {
      return 'Due in $difference days';
    } else {
      return 'Overdue';
    }
  }

  void _showSnackBar(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Color(0xFF47C272),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickImageFromGallery(Task task) async {
    // Show image source selection bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          margin: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(height: 20),

                // Title
                Text(
                  'Upload Photo for Task',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),

                Text(
                  'Choose how you want to add a photo',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),

                // Camera option
                _buildImageSourceOption(
                  icon: Icons.camera_alt,
                  title: 'Take Photo',
                  subtitle: 'Use camera to take a new photo',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(task, ImageSource.camera);
                  },
                ),
                SizedBox(height: 12),

                // Gallery option
                _buildImageSourceOption(
                  icon: Icons.photo_library,
                  title: 'Choose from Gallery',
                  subtitle: 'Select an existing photo',
                  color: Colors.green,
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(task, ImageSource.gallery);
                  },
                ),
                SizedBox(height: 20),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(Task task, ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImages[task.id] = image.path;
        });

        // Show confirmation dialog
        bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            /*return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.photo_camera, color: Color(0xFF643FDB)),
                  SizedBox(width: 8),
                  Text('Confirm Photo Upload'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to upload this photo and complete the task?',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Task: ${task.taskName}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Allowance: +${task.allowance.toStringAsFixed(0)} ﷼',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[600],
                    ),
                  ),
                  SizedBox(height: 16),
                  // Image preview
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(image.path),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: Icon(Icons.error, color: Colors.red),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF643FDB),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Upload & Complete'),
                ),
              ],*/
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Row(
                      children: [
                        Icon(Icons.photo_camera, color: Color(0xFF643FDB)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Confirm Photo Upload',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Content
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Are you sure you want to upload this photo and complete the task?',
                              style: TextStyle(fontSize: 16),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Task: ${task.taskName}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Allowance: +${task.allowance.toStringAsFixed(0)} ﷼',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[600],
                              ),
                            ),
                            SizedBox(height: 16),
                            // Image preview
                            Container(
                              height: 120,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(image.path),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: Icon(
                                        Icons.error,
                                        color: Colors.red,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pop(false);
                            },
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF643FDB),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(
                              'Upload & Complete',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (confirmed == true) {
          await _uploadImageAndCompleteTask(task, image);
        } else {
          // Remove the selected image if user cancelled
          setState(() {
            _selectedImages.remove(task.id);
          });
        }
      }
    } catch (e) {
      _showSnackBar('Failed to pick image: ${e.toString()}', true);
    }
  }

  Future<void> _uploadImageAndCompleteTask(Task task, XFile imageFile) async {
    // Check if task is overdue
    if (_isTaskOverdue(task)) {
      final daysOverdue = DateTime.now().difference(task.dueDate!).inDays;
      final overdueText = daysOverdue == 0 
          ? 'today' 
          : daysOverdue == 1 
              ? '1 day ago' 
              : '$daysOverdue days ago';
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Task Overdue'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This task is overdue and cannot be completed.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red[700],
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Task: ${task.taskName}\nDue: $overdueText',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please contact your parent to update the due date or mark the task as complete.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text('OK'),
              ),
            ],
          );
        },
      );
      
      // Remove the selected image since we can't complete
      setState(() {
        _selectedImages.remove(task.id);
      });
      return; // Exit early, don't allow completion
    }
    
    setState(() {
      _uploadingImages[task.id] = true;
    });

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Uploading Photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Uploading your photo and completing task...'),
              ],
            ),
          );
        },
      );

      // Upload image to Firebase Storage
      String imageUrl = await _haseelaService.uploadTaskImage(
        _currentParentId,
        _currentChildId,
        task.id,
        imageFile,
      );

      // Update task status with image URL
      await _haseelaService.updateTaskStatusWithImage(
        _currentParentId,
        _currentChildId,
        task.id,
        'pending',
        imageUrl,
      );

      await _tasksRef().doc(task.id).update({
        'completedDate': FieldValue.serverTimestamp(),
      });

      // Close loading dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show success message
      _showSnackBar(
        'Photo uploaded successfully! Task completed and waiting for parent approval. +${task.allowance.toStringAsFixed(0)} ﷼',
        false,
      );

      // Clear the selected image
      setState(() {
        _selectedImages.remove(task.id);
      });
    } catch (e) {
      // Close loading dialog safely
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      _showSnackBar('Failed to upload photo: ${e.toString()}', true);
    } finally {
      setState(() {
        _uploadingImages[task.id] = false;
      });
    }
  }

  /// Check if a task is overdue
  bool _isTaskOverdue(Task task) {
    if (task.dueDate == null) return false;
    final now = DateTime.now();
    // Remove time component for date comparison
    final dueDate = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
    final today = DateTime(now.year, now.month, now.day);
    return dueDate.isBefore(today);
  }

  Future<void> _completeTaskWithoutPhoto(Task task) async {
    // Check if task is overdue
    if (_isTaskOverdue(task)) {
      final daysOverdue = DateTime.now().difference(task.dueDate!).inDays;
      final overdueText = daysOverdue == 0 
          ? 'today' 
          : daysOverdue == 1 
              ? '1 day ago' 
              : '$daysOverdue days ago';
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Task Overdue'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This task is overdue and cannot be completed.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red[700],
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Task: ${task.taskName}\nDue: $overdueText',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please contact your parent to update the due date or mark the task as complete.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text('OK'),
              ),
            ],
          );
        },
      );
      return; // Exit early, don't allow completion
    }
    
    // Show confirmation dialog
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text('Complete Task'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to complete this task?',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Task: ${task.taskName}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Allowance: +${task.allowance.toStringAsFixed(0)} ﷼',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[600],
                ),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will mark the task as pending for parent approval.',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF47C272),
                foregroundColor: Colors.white,
              ),
              child: Text('Complete Task'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Completing Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Marking task as complete...'),
                ],
              ),
            );
          },
        );

        // Update task status to pending (without image)
        await _haseelaService.updateTaskStatus(
          _currentParentId,
          _currentChildId,
          task.id,
          'pending',
        );
        await _tasksRef().doc(task.id).update({
          'completedDate': FieldValue.serverTimestamp(),
        });
        // Close loading dialog
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Show success message
        _showSnackBar(
          'Task completed! Waiting for parent to approve +${task.allowance.toStringAsFixed(0)} ﷼',
          false,
        );
      } catch (e) {
        // Close loading dialog safely
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Show error message
        _showSnackBar('Failed to complete task: ${e.toString()}', true);
      }
    }
  }

  // Helper method to build task images with proper error handling
  Widget _buildTaskImage(String imagePath) {
    print('🔍 Building image for path: $imagePath');

    // Handle blob URLs and invalid paths
    if (imagePath.startsWith('blob:') || imagePath.isEmpty) {
      print('❌ Blob URL or empty path detected: $imagePath');
      return Container(
        color: Colors.grey[200],
        child: Icon(
          Icons.image_not_supported,
          color: Colors.grey[400],
          size: 24,
        ),
      );
    }

    // Handle HTTP URLs
    if (imagePath.startsWith('http')) {
      print('🌐 Network image URL detected: $imagePath');
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('❌ Error loading network image: $error');
          return Container(
            color: Colors.grey[200],
            child: Icon(Icons.error, color: Colors.red[400]),
          );
        },
      );
    }

    // Handle local file paths
    print('📁 Local file path detected: $imagePath');
    try {
      return Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Error loading local image: $error');
          return Container(
            color: Colors.grey[200],
            child: Icon(Icons.error, color: Colors.red[400]),
          );
        },
      );
    } catch (e) {
      print('❌ Error with local file path: $e');
      return Container(
        color: Colors.grey[200],
        child: Icon(Icons.image_not_supported, color: Colors.grey[400]),
      );
    }
  }

  void _showImageDialog(String imagePath) {
    // Don't show dialog for blob URLs or invalid paths
    if (imagePath.startsWith('blob:') || imagePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with close button
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Task Completion Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Image
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      child: imagePath.startsWith('http')
                          ? Image.network(
                              imagePath,
                              fit: BoxFit.contain,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Color(0xFF333333),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress
                                                        .expectedTotalBytes!
                                              : null,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                print('Error loading image in dialog: $error');
                                return Container(
                                  color: Color(0xFF333333),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Error loading image',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          : Image.file(
                              File(imagePath),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                print(
                                  'Error loading local image in dialog: $error',
                                );
                                return Container(
                                  color: Color(0xFF333333),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Error loading image',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to get priority display information
  Map<String, dynamic> _getPriorityInfo(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return {
          'text': 'High Priority',
          'color': Colors.red,
          'icon': Icons.priority_high,
        };
      case 'medium':
        return {
          'text': 'Medium Priority',
          'color': Colors.orange,
          'icon': Icons.remove,
        };
      case 'low':
        return {
          'text': 'Low Priority',
          'color': Colors.green,
          'icon': Icons.keyboard_arrow_down,
        };
      default:
        return {
          'text': 'Normal Priority',
          'color': Colors.grey,
          'icon': Icons.circle,
        };
    }
  }

  String? _getTaskImage(Task task) {
    // Prefer the new 'image' field, fallback to 'completedImagePath'
    return task.image ?? task.completedImagePath;
  }
}
