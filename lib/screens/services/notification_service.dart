import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<QuerySnapshot>? _tasksSubscription;
  StreamSubscription<QuerySnapshot>?
  _parentTasksSubscription; // For parent notifications
  StreamSubscription<QuerySnapshot>?
  _parentChildrenSubscription; // For listening to children list
  StreamSubscription<RemoteMessage>? _fcmForegroundSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _lastNotifiedTaskId;
  String? _lastNotifiedParentTaskId; // Track last notified task for parent
  final Map<String, String> _taskStatusCache = {}; // taskId -> previous status
  final Map<String, String> _parentTaskStatusCache =
      {}; // taskId -> previous status for parent
  final Map<String, StreamSubscription<QuerySnapshot>> _childTaskSubscriptions =
      {}; // childId -> subscription
  final Map<String, StreamSubscription<QuerySnapshot>>
      _childWishlistSubscriptions = {}; // childId -> wishlist subscription
  final Map<String, bool> _wishlistItemCompletionCache =
      {}; // wishlistItemId -> isCompleted status
  final Set<String> _notifiedNewTasks =
      {}; // Track which new tasks have been notified
  final Map<String, Timestamp?> _taskDueDateCache =
      {}; // taskId -> previous dueDate (to detect changes)
  bool _cacheInitialized = false; // Track if cache has been initialized
  bool _parentCacheInitialized =
      false; // Track if parent cache has been initialized
  bool _firstSnapshotReceived =
      false; // Track if first snapshot from listener has been received
  Timer? _overdueTaskCheckTimer;
  final Set<String> _notifiedOverdueTasks =
      {}; // taskId -> already notified (only once per task/dueDate combination)
  String? _currentParentId;
  String? _currentChildId;

  Future<void> initializeForChild({
    required String parentId,
    required String childId,
  }) async {
    // ignore: avoid_print
    print('🚀 ===== NOTIFICATION SERVICE INIT START =====');
    // ignore: avoid_print
    print(
      '🚀 Initializing notifications for child: $childId (parent: $parentId)',
    );

    // Store parent and child IDs for overdue task checking
    _currentParentId = parentId;
    _currentChildId = childId;
    try {
      // Step 1: Initialize local notifications FIRST (works always, even without FCM)
      // ignore: avoid_print
      print('📱 Step 1: Initializing local notifications...');
      await _initializeLocalNotifications();
      // ignore: avoid_print
      print('✅ Step 1: Local notifications initialized');

      // Step 2: Try to get FCM token FIRST (before requesting permission)
      // ignore: avoid_print
      print('📱 Step 2: Getting FCM token...');
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          // ignore: avoid_print
          print('🔑 FCM token obtained: ${token.substring(0, 20)}...');
          await _saveToken(parentId: parentId, childId: childId, token: token);
        } else {
          // ignore: avoid_print
          print('⚠️ FCM token is null or empty');
        }
      } catch (tokenError) {
        // ignore: avoid_print
        print(
          '⚠️ Could not get FCM token yet (may need permission): $tokenError',
        );
      }

      // Step 3: Request FCM permission (for push when app is closed)
      // ignore: avoid_print
      print('📱 Step 3: Requesting FCM permission...');
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        // ignore: avoid_print
        print('📱 FCM Permission status: ${settings.authorizationStatus}');

        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          await _messaging.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );

          // Try to get token again after permission granted
          final tokenAfterPermission = await _messaging.getToken();
          if (tokenAfterPermission != null && tokenAfterPermission.isNotEmpty) {
            // ignore: avoid_print
            print(
              '🔑 FCM token after permission: ${tokenAfterPermission.substring(0, 20)}...',
            );
            await _saveToken(
              parentId: parentId,
              childId: childId,
              token: tokenAfterPermission,
            );
          }
        }
      } catch (permissionError) {
        // ignore: avoid_print
        print('⚠️ Error requesting permission: $permissionError');
      }

      // Step 4: Setup token refresh listener (important!)
      // ignore: avoid_print
      print('📱 Step 4: Setting up token refresh listener...');
      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((
        newToken,
      ) async {
        // ignore: avoid_print
        print('♻️ FCM token refreshed: ${newToken.substring(0, 20)}...');
        await _saveToken(parentId: parentId, childId: childId, token: newToken);
      });

      // Step 5: Handle FCM foreground messages (backup - Firestore listener is primary)
      // ignore: avoid_print
      print('📱 Step 5: Setting up FCM foreground message handler...');
      _fcmForegroundSubscription ??= FirebaseMessaging.onMessage.listen((
        RemoteMessage message,
      ) {
        final notif = message.notification;
        final messageType = message.data['type'] ?? 'task_approval';
        final isOverdueTask = messageType == 'overdue_task';
        final isReminderToday = messageType == 'task_reminder_today';
        final isReminderTomorrow = messageType == 'task_reminder_tomorrow';
        
        if (notif != null) {
          // ignore: avoid_print
          print('📩 FCM (foreground): ${notif.title} - ${notif.body} (type: $messageType)');
          
          // For overdue tasks or reminders, use foreground service channel to ensure it shows
          if (isOverdueTask || isReminderToday || isReminderTomorrow) {
            _showOverdueTaskNotificationFromFCM(
              title: notif.title ?? 'Task Notification',
              body: notif.body ?? '',
            );
          } else {
          _showLocalNotification(
            title: notif.title ?? 'Notification',
            body: notif.body ?? '',
          );
          }
        }
      });

      // Step 6: ✅ PRIMARY METHOD: Listen to Firestore task changes directly
      // This works even if FCM fails - detects changes immediately
      // ignore: avoid_print
      print('📱 Step 6: Setting up Firestore task listener...');
      _listenToTaskChanges(parentId, childId);

      // Step 7: Start periodic overdue task checking
      // ignore: avoid_print
      print('📱 Step 7: Starting overdue task checker...');
      _startOverdueTaskChecker(parentId, childId);

      // ignore: avoid_print
      print('✅ ===== NOTIFICATION SERVICE INIT COMPLETE =====');
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('❌ ===== ERROR INITIALIZING NOTIFICATIONS =====');
      // ignore: avoid_print
      print('❌ Error: $e');
      // ignore: avoid_print
      print('❌ Stack trace: $stackTrace');
      // Even if FCM fails, we should still setup Firestore listener
      try {
        // ignore: avoid_print
        print('🔄 Attempting to setup Firestore listener as fallback...');
        _listenToTaskChanges(parentId, childId);
      } catch (fallbackError) {
        // ignore: avoid_print
        print('❌ Even Firestore listener failed: $fallbackError');
      }
    }
  }

  Future<void> initializeForParent({required String parentId}) async {
    // ignore: avoid_print
    print('🚀 ===== PARENT NOTIFICATION SERVICE INIT START =====');
    // ignore: avoid_print
    print('🚀 Initializing notifications for parent: $parentId');

    try {
      // Step 1: Initialize local notifications FIRST (works always, even without FCM)
      // ignore: avoid_print
      print('📱 Step 1: Initializing local notifications...');
      await _initializeLocalNotifications();
      // ignore: avoid_print
      print('✅ Step 1: Local notifications initialized');

      // Step 2: Try to get FCM token FIRST (before requesting permission)
      // ignore: avoid_print
      print('📱 Step 2: Getting FCM token...');
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          // ignore: avoid_print
          print('🔑 FCM token obtained: ${token.substring(0, 20)}...');
          // Note: For parent, we might want to save token differently
          // For now, we'll just use it for FCM if needed
        } else {
          // ignore: avoid_print
          print('⚠️ FCM token is null or empty');
        }
      } catch (tokenError) {
        // ignore: avoid_print
        print(
          '⚠️ Could not get FCM token yet (may need permission): $tokenError',
        );
      }

      // Step 3: Request FCM permission (for push when app is closed)
      // ignore: avoid_print
      print('📱 Step 3: Requesting FCM permission...');
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        // ignore: avoid_print
        print('📱 FCM Permission status: ${settings.authorizationStatus}');

        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          await _messaging.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
        }
      } catch (permissionError) {
        // ignore: avoid_print
        print('⚠️ Error requesting permission: $permissionError');
      }

      // Step 4: Setup token refresh listener (important!)
      // ignore: avoid_print
      print('📱 Step 4: Setting up token refresh listener...');
      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((
        newToken,
      ) async {
        // ignore: avoid_print
        print('♻️ FCM token refreshed: ${newToken.substring(0, 20)}...');
      });

      // Step 5: Handle FCM foreground messages (backup - Firestore listener is primary)
      // ignore: avoid_print
      print('📱 Step 5: Setting up FCM foreground message handler...');
      _fcmForegroundSubscription ??= FirebaseMessaging.onMessage.listen((
        RemoteMessage message,
      ) {
        final notif = message.notification;
        if (notif != null) {
          // ignore: avoid_print
          print('📩 FCM (foreground): ${notif.title} - ${notif.body}');
          _showParentNotification(
            title: notif.title ?? 'Notification',
            body: notif.body ?? '',
          );
        }
      });

      // Step 6: ✅ PRIMARY METHOD: Listen to Firestore task changes for all children
      // This works even if FCM fails - detects changes immediately
      // ignore: avoid_print
      print(
        '📱 Step 6: Setting up Firestore task listener for all children...',
      );
      _listenToParentTaskChanges(parentId);

      // ignore: avoid_print
      print('✅ ===== PARENT NOTIFICATION SERVICE INIT COMPLETE =====');
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('❌ ===== ERROR INITIALIZING PARENT NOTIFICATIONS =====');
      // ignore: avoid_print
      print('❌ Error: $e');
      // ignore: avoid_print
      print('❌ Stack trace: $stackTrace');
      // Even if FCM fails, we should still setup Firestore listener
      try {
        // ignore: avoid_print
        print('🔄 Attempting to setup Firestore listener as fallback...');
        _listenToParentTaskChanges(parentId);
      } catch (fallbackError) {
        // ignore: avoid_print
        print('❌ Even Firestore listener failed: $fallbackError');
      }
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Android initialization
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        // ignore: avoid_print
        print('📲 Notification tapped: ${response.payload}');
      },
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      // Channel for child notifications (task approvals)
      const AndroidNotificationChannel childChannel =
          AndroidNotificationChannel(
            'task_approval_channel',
            'Task Approvals',
            description: 'Notifications when parent approves your tasks',
            importance: Importance.high,
            playSound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(childChannel);

      // Channel for task rejections (parent declines)
      const AndroidNotificationChannel rejectionChannel =
          AndroidNotificationChannel(
            'task_rejection_channel',
            'Task Rejections',
            description: 'Notifications when parent declines your tasks',
            importance: Importance
                .max, // Max importance to always show in notification bar
            playSound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(rejectionChannel);

      // Channel for new task assignments
      const AndroidNotificationChannel newTaskChannel =
          AndroidNotificationChannel(
            'new_task_channel',
            'New Tasks',
            description: 'Notifications when parent assigns you a new task',
            importance: Importance
                .max, // Max importance to always show in notification bar
            playSound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(newTaskChannel);

      // Channel for overdue task notifications
      const AndroidNotificationChannel overdueTaskChannel =
          AndroidNotificationChannel(
        'overdue_task_channel',
        'Overdue Tasks',
        description: 'Notifications when your tasks are overdue',
        importance: Importance
            .max, // Max importance to always show in notification bar
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(overdueTaskChannel);
      // Channel for parent notifications (task completions)
      const AndroidNotificationChannel parentChannel =
          AndroidNotificationChannel(
            'task_completion_channel',
            'Task Completions',
            description: 'Notifications when your child completes a task',
            importance: Importance
                .max, // Max importance to always show in notification bar
            playSound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(parentChannel);

      // Channel for parent task rejections (confirmation/reminders)
      const AndroidNotificationChannel parentRejectionChannel =
          AndroidNotificationChannel(
            'parent_task_rejection_channel',
            'Task Rejections (Parent)',
            description: 'Notifications when you decline a submitted task',
            importance: Importance
                .max, // Max importance to always show in notification bar
            playSound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(parentRejectionChannel);

      // Channel for wishlist milestone completions (parent notifications)
      const AndroidNotificationChannel wishlistMilestoneChannel =
          AndroidNotificationChannel(
            'wishlist_milestone_channel',
            'Wishlist Milestones',
            description:
                'Notifications when your child completes a wishlist milestone',
            importance: Importance
                .max, // Max importance to always show in notification bar
            playSound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(wishlistMilestoneChannel);

      // Request notification permission for Android 13+
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        final granted = await androidImplementation
            .requestNotificationsPermission();
        // ignore: avoid_print
        print('📱 Android notification permission: $granted');
      }
    }

    // ignore: avoid_print
    print('✅ Local notifications initialized');
  }

  // Helper method to normalize task status
  String _normalizeStatus(String status) {
    final lower = status.toLowerCase().trim();
    // Normalize all "done" variations to 'done'
    if (lower == 'completed' ||
        lower == 'approved' ||
        lower == 'complete' ||
        lower == 'done')
      return 'done';
    // Keep pending as pending
    if (lower == 'pending') return 'pending';
    // Keep rejected as rejected
    if (lower == 'rejected') return 'rejected';
    // Keep new/incomplete as 'new'
    if (lower == 'new' || lower == 'incomplete' || lower == 'assigned')
      return 'new';
    return lower;
  }

  void _listenToTaskChanges(String parentId, String childId) {
    // ignore: avoid_print
    print('👂 Setting up Firestore listener for task changes...');

    _tasksSubscription?.cancel();
    _taskStatusCache.clear(); // Clear cache when reinitializing
    _notifiedNewTasks.clear(); // Clear notified new tasks cache
    _firstSnapshotReceived = false; // Reset first snapshot flag
    // First, initialize the cache with current task statuses
    FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Tasks')
        .get()
        .then((QuerySnapshot initialSnapshot) {
          // ignore: avoid_print
          print(
            '📋 Initializing cache with ${initialSnapshot.docs.length} existing tasks',
          );
          for (var doc in initialSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final rawStatus = (data['status'] ?? '').toString();
            final normalizedStatus = _normalizeStatus(rawStatus);
            _taskStatusCache[doc.id] = normalizedStatus;

            // Also cache the dueDate so we can detect changes
            final dueDate = data['dueDate'] as Timestamp?;
            if (dueDate != null) {
              _taskDueDateCache[doc.id] = dueDate;
            }

            // ignore: avoid_print
            print(
              '📋 Cached task ${doc.id}: "$rawStatus" → "$normalizedStatus", dueDate=${dueDate != null ? "cached" : "null"}',
            );
          }
          // ignore: avoid_print
          print(
            '✅ Cache initialized with ${_taskStatusCache.length} tasks. Now listening for changes...',
          );
          _cacheInitialized = true; // Mark cache as ready
          // ignore: avoid_print
          print('✅ Cache initialization flag set to true');
        })
        .catchError((error) {
          // ignore: avoid_print
          print('⚠️ Error initializing cache: $error');
          _cacheInitialized =
              true; // Mark as initialized even on error to allow listener to work
          // ignore: avoid_print
          print(
            '⚠️ Cache initialization flag set to true despite error (allowing listener to work)',
          );
        });
    // ✅ PRIMARY METHOD: Listen to ALL tasks and detect status changes from pending->done
    // This works even if FCM fails - detects Firestore changes directly
    // ignore: avoid_print
    print('🔧 Setting up Firestore task listener for parentId: $parentId, childId: $childId');
    _tasksSubscription = FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Tasks')
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
        // ignore: avoid_print
        print('📊 Firestore task listener triggered - ${snapshot.docChanges.length} changes (cacheInitialized: $_cacheInitialized, firstSnapshotReceived: $_firstSnapshotReceived)');
        // ignore: avoid_print
        print('📊 Listener is ACTIVE - received snapshot with ${snapshot.docs.length} total documents');
        // ignore: avoid_print
        print('   Snapshot metadata: hasPendingWrites=${snapshot.metadata.hasPendingWrites}, isFromCache=${snapshot.metadata.isFromCache}');
        
        // IMPORTANT: Track if this is the first snapshot BEFORE processing changes
        // This way, we can distinguish between initial load (first snapshot) and truly new tasks
        final isFirstSnapshot = !_firstSnapshotReceived;
        
        // ignore: avoid_print
        print('📊 Processing snapshot: isFirstSnapshot=$isFirstSnapshot, _firstSnapshotReceived=$_firstSnapshotReceived, changes=${snapshot.docChanges.length}');
        
        // If cache not initialized yet, we'll still process but be more careful about notifications
        // This prevents missing changes that happen during initialization
        
        // Check for status changes
        for (var docChange in snapshot.docChanges) {
          // ignore: avoid_print
          print('📝 Task change: ${docChange.type} - ID: ${docChange.doc.id}');
          
          if (docChange.type == DocumentChangeType.modified) {
            final newData = docChange.doc.data() as Map<String, dynamic>;
            final taskId = docChange.doc.id;
            
            // IMPORTANT: Always check dueDate changes FIRST, even if status didn't change
            // This ensures we catch dueDate changes made directly in Firestore
            final newDueDate = newData['dueDate'] as Timestamp?;
            final now = DateTime.now();
            
            // ignore: avoid_print
            print('📝 Task MODIFIED: $taskId - Checking for dueDate changes...');
            // ignore: avoid_print
            print('🔍 DueDate check for task $taskId: newDueDate=$newDueDate');
            
            final newStatus = (newData['status'] ?? '').toString();
            final normalizedNewStatus = _normalizeStatus(newStatus);
            
            // ignore: avoid_print
            print('🔍 Task $taskId modified - status: $newStatus, dueDate: $newDueDate');
            
            // Get previous status from cache BEFORE updating it
            final oldStatus = _taskStatusCache[taskId] ?? '';
            final normalizedOldStatus = oldStatus.isNotEmpty ? _normalizeStatus(oldStatus) : '';
            
            // If cache wasn't initialized, we need to be smarter - check if this is a real change
            // by looking at completedDate timestamp - if it's very recent, it's likely a new completion
            final completedDate = newData['completedDate'] as Timestamp?;
            final isRecentCompletion = completedDate != null && 
                completedDate.toDate().isAfter(now.subtract(const Duration(minutes: 5)));

            // ignore: avoid_print
            print('   Cache initialized: $_cacheInitialized, isRecentCompletion: $isRecentCompletion');
            
            // Update cache AFTER we've checked the change
            _taskStatusCache[taskId] = normalizedNewStatus;
            
            // ✅ Check if task status changed from "pending" to "done" (parent approved task)
            // This sends a notification to the child when parent approves their completed task
            final changedToDone = normalizedOldStatus == 'pending' && normalizedNewStatus == 'done';
            final changedToDoneWithoutCache = !_cacheInitialized && 
                                             normalizedNewStatus == 'done' && 
                                             isRecentCompletion;
            
            if (changedToDone || changedToDoneWithoutCache) {
                  final taskName = newData['taskName'] ?? 'Your task';
                  // ignore: avoid_print
              print('✅ Task "$taskName" approved! Status changed from pending → done. Sending notification to child.');
              _showLocalNotification(
                title: 'Task approved! 🎉',
                body: '$taskName has been approved!',
              );
            }
            
            // ✅ Check if task status changed from "pending" to "rejected" (parent rejected task)
            // This sends a notification to the child when parent rejects their completed task
            final changedToRejected = normalizedOldStatus == 'pending' && normalizedNewStatus == 'rejected';
            final changedToRejectedWithoutCache = !_cacheInitialized && 
                                                 normalizedNewStatus == 'rejected' && 
                                                 isRecentCompletion;
            
            if (changedToRejected || changedToRejectedWithoutCache) {
              final taskName = newData['taskName'] ?? 'Your task';
              // ignore: avoid_print
              print('❌ Task "$taskName" rejected! Status changed from pending → rejected. Sending notification to child.');
              _showTaskRejectedNotification(
                title: 'Task Rejected ❌',
                body: '$taskName was not approved. Please try again.',
              );
            }
            
            // Always check dueDate if it exists (don't require parentId/childId since listener is already scoped)
            if (newDueDate != null) {
              final dueDateTime = newDueDate.toDate();
              final isOverdue = dueDateTime.isBefore(now);
              final isNewStatus = normalizedNewStatus == 'new';
              
              // Get old dueDate from cache
              final oldDueDate = _taskDueDateCache[taskId];
              
              // ignore: avoid_print
              print('🔍 DueDate cache: oldDueDate=$oldDueDate (${oldDueDate != null ? "seconds=${oldDueDate.seconds}, nanos=${oldDueDate.nanoseconds}" : "null"}), newDueDate=$newDueDate (seconds=${newDueDate.seconds}, nanos=${newDueDate.nanoseconds})');
              
              // Compare Timestamps properly - check if they're different
              bool dueDateChanged = false;
              if (oldDueDate == null) {
                dueDateChanged = true; // First time we see this dueDate
                  // ignore: avoid_print
                print('🔍 DueDate changed: First time seeing this dueDate (oldDueDate was null)');
              } else {
                // Compare the actual timestamp values
                final oldSeconds = oldDueDate.seconds;
                final newSeconds = newDueDate.seconds;
                final oldNanos = oldDueDate.nanoseconds;
                final newNanos = newDueDate.nanoseconds;
                dueDateChanged = (oldSeconds != newSeconds) || (oldNanos != newNanos);
                // ignore: avoid_print
                print('🔍 DueDate comparison: oldSeconds=$oldSeconds, newSeconds=$newSeconds, oldNanos=$oldNanos, newNanos=$newNanos, dueDateChanged=$dueDateChanged');
              }
              
              // Check if old dueDate was overdue
              bool wasOverdueBefore = false;
              if (oldDueDate != null) {
                final oldDueDateTime = oldDueDate.toDate();
                wasOverdueBefore = oldDueDateTime.isBefore(now);
              }
              
              // Use notification key based on taskId and dueDate to allow re-notification if dueDate changes
              final notificationKey = '$taskId:${newDueDate.seconds}:${newDueDate.nanoseconds}';
              final alreadyNotified = _notifiedOverdueTasks.contains(notificationKey);
            
            // ignore: avoid_print
              print('🔍 DueDate check: dueDateTime=$dueDateTime, now=$now, isOverdue=$isOverdue, wasOverdueBefore=$wasOverdueBefore, isNewStatus=$isNewStatus, alreadyNotified=$alreadyNotified, dueDateChanged=$dueDateChanged');
              
              // Update dueDate cache
              _taskDueDateCache[taskId] = newDueDate;
              
              // Check if due date is today or tomorrow (for reminder notifications)
              // IMPORTANT: We compare only the date part (year, month, day) to determine if it's today/tomorrow
              final dueDateOnly = DateTime(dueDateTime.year, dueDateTime.month, dueDateTime.day);
              final todayOnly = DateTime(now.year, now.month, now.day);
              final tomorrowOnly = todayOnly.add(const Duration(days: 1));
              final isDueDateToday = dueDateOnly.isAtSameMomentAs(todayOnly);
              final isDueDateTomorrow = dueDateOnly.isAtSameMomentAs(tomorrowOnly);
              
              // Check for reminder notifications (due today or tomorrow)
              if (isDueDateToday && isNewStatus) {
                final reminderKey = 'reminder_today_$taskId:${newDueDate.seconds}:${newDueDate.nanoseconds}';
                if (!_notifiedOverdueTasks.contains(reminderKey)) {
                  _notifiedOverdueTasks.add(reminderKey);
                  final taskName = newData['taskName'] ?? 'A task';
            // ignore: avoid_print
                  print('📅 Task $taskId is due today! Sending reminder notification.');
                  _showTaskReminderNotification(taskName: taskName, isDueToday: true);
                }
              } else if (isDueDateTomorrow && isNewStatus) {
                final reminderKey = 'reminder_tomorrow_$taskId:${newDueDate.seconds}:${newDueDate.nanoseconds}';
                if (!_notifiedOverdueTasks.contains(reminderKey)) {
                  _notifiedOverdueTasks.add(reminderKey);
                  final taskName = newData['taskName'] ?? 'A task';
            // ignore: avoid_print
                  print('📅 Task $taskId is due tomorrow! Sending reminder notification.');
                  _showTaskReminderNotification(taskName: taskName, isDueToday: false);
                }
              }
              
              // Check for overdue notifications (past due, not today)
              if (!isDueDateToday && !isDueDateTomorrow) {
                // IMPORTANT: If dueDate changed, clear ALL notification keys for this task
                // This ensures we can re-notify when dueDate changes, even if we notified before
                // This is critical when user changes dueDate in database
                if (dueDateChanged && oldDueDate != null) {
                  // Remove any existing notification keys for this task (regardless of dueDate)
                  final keysToRemove = _notifiedOverdueTasks.where((key) => key.startsWith('$taskId:')).toList();
                  for (var key in keysToRemove) {
                    _notifiedOverdueTasks.remove(key);
              // ignore: avoid_print
                    print('🔄 Task $taskId dueDate changed, clearing old notification key: $key');
                  }
                }
                
                // DEBUG: Log current state
              // ignore: avoid_print
                print('🔍 Task $taskId state: isOverdue=$isOverdue, isNewStatus=$isNewStatus, dueDateChanged=$dueDateChanged, oldDueDate=$oldDueDate, notificationKey=$notificationKey, _notifiedOverdueTasks contains key=${_notifiedOverdueTasks.contains(notificationKey)}');
                
                // If dueDate changed to a future date (no longer overdue), we're done
                if (!isOverdue && wasOverdueBefore && oldDueDate != null) {
              // ignore: avoid_print
                  print('✅ Task $taskId is no longer overdue (dueDate changed to future date)');
                } else if (isOverdue && isNewStatus) {
                  // Task is overdue and status is 'new' - check if we should notify
                  // Key insight: If dueDate changed to an overdue date, we should always notify
                  // This handles the case where user changes dueDate in database to make task overdue
                  
                  // CRITICAL FIX: For modification events, always clear the notification key for this specific dueDate
                  // This ensures that when user changes dueDate in database, we can re-notify even if:
                  // 1. The cache already has the new dueDate (dueDateChanged=false)
                  // 2. We've notified for this dueDate before (maybe from a previous check)
                  // 
                  // This is important because Firestore modifications should always allow re-notification
                  // if the task becomes overdue, regardless of cache state
                  if (_notifiedOverdueTasks.contains(notificationKey)) {
                    _notifiedOverdueTasks.remove(notificationKey);
              // ignore: avoid_print
                    print('🔄 Task $taskId modification detected - clearing notification key to allow re-notification: $notificationKey');
                  }
                  
                  // Re-check after clearing
                  final alreadyNotifiedAfterClear = _notifiedOverdueTasks.contains(notificationKey);
                  
                  // IMPORTANT: We should notify if:
                  // 1. dueDate changed (user changed it in database) - always notify
                  // 2. oldDueDate was null (first time seeing this task with dueDate) - always notify
                  // 3. We haven't notified for this specific dueDate yet (after clearing above)
                  // 
                  // Since we just cleared the notification key above for modification events,
                  // alreadyNotifiedAfterClear should be false, allowing us to notify
                  final shouldNotify = dueDateChanged || 
                                      oldDueDate == null || 
                                      !alreadyNotifiedAfterClear;
                  
              // ignore: avoid_print
                  print('🔍 Notification decision: isOverdue=$isOverdue, isNewStatus=$isNewStatus, isDueDateToday=$isDueDateToday, dueDateChanged=$dueDateChanged, oldDueDate=$oldDueDate, wasOverdueBefore=$wasOverdueBefore, alreadyNotifiedAfterClear=$alreadyNotifiedAfterClear, shouldNotify=$shouldNotify');
                  
                  if (shouldNotify) {
                    _notifiedOverdueTasks.add(notificationKey);
                    final taskName = newData['taskName'] ?? 'A task';
                    final daysOverdue = now.difference(dueDateOnly).inDays;
                    // Ensure daysOverdue is at least 1 (should be since we excluded today)
                    if (daysOverdue >= 1) {
              // ignore: avoid_print
                      print('⏰ Task $taskId is overdue! Sending notification. Days overdue: $daysOverdue, dueDateChanged=$dueDateChanged');
                      _showOverdueTaskNotification(taskName: taskName, daysOverdue: daysOverdue);
                    } else {
                      // ignore: avoid_print
                      print('⏭️ Skipping notification for task $taskId - due date is today (daysOverdue=$daysOverdue)');
                    }
                  } else {
                    // ignore: avoid_print
                    print('⏭️ Skipping notification for task $taskId - shouldNotify=false (dueDateChanged=$dueDateChanged, oldDueDate=$oldDueDate, alreadyNotifiedAfterClear=$alreadyNotifiedAfterClear)');
                  }
                } else if (!isOverdue) {
                  // ignore: avoid_print
                  print('⏭️ Skipping notification for task $taskId - not overdue');
                } else if (!isNewStatus) {
                  // ignore: avoid_print
                  print('⏭️ Skipping notification for task $taskId - status is not "new" (status: $normalizedNewStatus)');
                }
              }
            }
          } else if (docChange.type == DocumentChangeType.added) {
            // Initialize new tasks in cache
            final data = docChange.doc.data() as Map<String, dynamic>;
            final rawStatus = (data['status'] ?? '').toString();
            final normalizedStatus = _normalizeStatus(rawStatus);
            final taskId = docChange.doc.id;
            _taskStatusCache[taskId] = normalizedStatus;
            
            // ✅ Check if this is a truly new task assignment
            // Notify if:
            // 1. It's not the first snapshot (truly new task added while app is running), OR
            // 2. It's the first snapshot BUT the task was created recently (within last 10 minutes)
            //    This handles the case where parent creates a task while child is logged out
            final createdAt = data['createdAt'] as Timestamp?;
            final now = DateTime.now();
            final isRecentlyCreated = createdAt != null && 
                createdAt.toDate().isAfter(now.subtract(const Duration(minutes: 10)));
            
            final shouldNotifyForNewTask = normalizedStatus == 'new' && 
                (!isFirstSnapshot || (isFirstSnapshot && isRecentlyCreated));
            
            if (shouldNotifyForNewTask) {
              // Check if we've already notified about this task
              if (!_notifiedNewTasks.contains(taskId)) {
                _notifiedNewTasks.add(taskId);
                final taskName = data['taskName'] ?? 'A new task';
                // ignore: avoid_print
                print('📝 New task assigned: "$taskName" (ID: $taskId). Sending notification to child.');
                // ignore: avoid_print
                print('   isFirstSnapshot=$isFirstSnapshot, isRecentlyCreated=$isRecentlyCreated, createdAt=${createdAt?.toDate()}');
                _showNewTaskNotification(
                  title: 'New Task Assigned! 📋',
                  body: 'You have a new task: $taskName',
                );
              } else {
                // ignore: avoid_print
                print('⏭️ Skipping new task notification for $taskId - already notified');
              }
            } else {
              if (isFirstSnapshot && !isRecentlyCreated) {
                // ignore: avoid_print
                print('⏭️ Skipping new task notification for $taskId - this is initial load and task is not recently created (createdAt=${createdAt?.toDate()})');
              } else if (normalizedStatus != 'new') {
                // ignore: avoid_print
                print('⏭️ Skipping new task notification for $taskId - status is not "new" (status: $normalizedStatus)');
              } else if (isFirstSnapshot && createdAt == null) {
                // ignore: avoid_print
                print('⏭️ Skipping new task notification for $taskId - no createdAt timestamp found');
              }
            }
            
            // Check if new task is overdue
            final dueDate = data['dueDate'] as Timestamp?;
            if (dueDate != null) {
              _taskDueDateCache[taskId] = dueDate;
              final dueDateTime = dueDate.toDate();
              final now = DateTime.now();
              final isOverdue = dueDateTime.isBefore(now);
              final isNewStatus = normalizedStatus == 'new';
              
              // Check if due date is today or tomorrow (for reminder notifications)
              // IMPORTANT: We compare only the date part (year, month, day) to determine if it's today/tomorrow
              final dueDateOnly = DateTime(dueDateTime.year, dueDateTime.month, dueDateTime.day);
              final todayOnly = DateTime(now.year, now.month, now.day);
              final tomorrowOnly = todayOnly.add(const Duration(days: 1));
              final isDueDateToday = dueDateOnly.isAtSameMomentAs(todayOnly);
              final isDueDateTomorrow = dueDateOnly.isAtSameMomentAs(tomorrowOnly);
              
              // Check for reminder notifications (due today or tomorrow)
              if (isDueDateToday && isNewStatus) {
                final reminderKey = 'reminder_today_$taskId:${dueDate.seconds}:${dueDate.nanoseconds}';
                if (!_notifiedOverdueTasks.contains(reminderKey)) {
                  _notifiedOverdueTasks.add(reminderKey);
                  final taskName = data['taskName'] ?? 'A task';
                // ignore: avoid_print
                  print('📅 New task $taskId is due today! Sending reminder notification.');
                  _showTaskReminderNotification(taskName: taskName, isDueToday: true);
                }
              } else if (isDueDateTomorrow && isNewStatus) {
                final reminderKey = 'reminder_tomorrow_$taskId:${dueDate.seconds}:${dueDate.nanoseconds}';
                if (!_notifiedOverdueTasks.contains(reminderKey)) {
                  _notifiedOverdueTasks.add(reminderKey);
                  final taskName = data['taskName'] ?? 'A task';
                  // ignore: avoid_print
                  print('📅 New task $taskId is due tomorrow! Sending reminder notification.');
                  _showTaskReminderNotification(taskName: taskName, isDueToday: false);
                }
              }
              
              // Check for overdue notifications (past due, not today or tomorrow)
              if (!isDueDateToday && !isDueDateTomorrow) {
                // Use notification key based on taskId and dueDate
                final notificationKey = '$taskId:${dueDate.seconds}:${dueDate.nanoseconds}';
                final alreadyNotified = _notifiedOverdueTasks.contains(notificationKey);
                
                // Only notify if task is overdue, status is 'new', and not already notified
                if (isOverdue && isNewStatus && !alreadyNotified) {
                  final daysOverdue = now.difference(dueDateOnly).inDays;
                  // Ensure daysOverdue is at least 1 (should be since we excluded today)
                  if (daysOverdue >= 1) {
                    _notifiedOverdueTasks.add(notificationKey);
                    final taskName = data['taskName'] ?? 'A task';
            // ignore: avoid_print
                    print('⏰ New task $taskId is overdue! Sending notification. Days overdue: $daysOverdue');
                    _showOverdueTaskNotification(taskName: taskName, daysOverdue: daysOverdue);
                  } else {
            // ignore: avoid_print
                    print('⏭️ Skipping notification for new task $taskId - due date is today (daysOverdue=$daysOverdue)');
                  }
                } else if (isOverdue && isNewStatus && alreadyNotified) {
            // ignore: avoid_print
                  print('⏭️ Skipping notification for new task $taskId - already notified for this dueDate');
                } else if (!isOverdue) {
            // ignore: avoid_print
                  print('⏭️ Skipping notification for new task $taskId - not overdue yet');
                } else if (!isNewStatus) {
            // ignore: avoid_print
                  print('⏭️ Skipping notification for new task $taskId - status is not "new"');
                }
              }
            }
          }
        }
        
        // Mark that we've received the first snapshot AFTER processing all changes
        // This ensures we can distinguish between initial load and truly new tasks
        if (!_firstSnapshotReceived) {
          _firstSnapshotReceived = true;
          // ignore: avoid_print
          print('✅ First snapshot processed. Future added tasks will trigger notifications.');
        }
      },
    );
  }

  void _listenToParentTaskChanges(String parentId) {
    // ignore: avoid_print
    print('👂 Setting up Firestore listener for parent task changes...');

    _parentTasksSubscription?.cancel();
    _parentTaskStatusCache.clear(); // Clear cache when reinitializing
    _parentCacheInitialized = false; // Reset initialization flag

    // First, initialize the cache with current task statuses for all children
    // This prevents false notifications on initial load
    FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .get()
        .then((childrenSnapshot) async {
      // ignore: avoid_print
      print('📋 Initializing parent cache with ${childrenSnapshot.docs.length} children');
      
      int totalTasks = 0;
      for (var childDoc in childrenSnapshot.docs) {
        final childId = childDoc.id;
        final tasksSnapshot = await FirebaseFirestore.instance
            .collection('Parents')
            .doc(parentId)
            .collection('Children')
            .doc(childId)
            .collection('Tasks')
            .get();
        
        for (var taskDoc in tasksSnapshot.docs) {
          final data = taskDoc.data() as Map<String, dynamic>;
          final rawStatus = (data['status'] ?? '').toString();
          final normalizedStatus = _normalizeStatus(rawStatus);
          final taskKey = '${childId}_${taskDoc.id}';
          _parentTaskStatusCache[taskKey] = normalizedStatus;
          totalTasks++;
        }
      }
      
      _parentCacheInitialized = true;
      // ignore: avoid_print
      print('📋 Parent cache initialized with $totalTasks tasks across ${childrenSnapshot.docs.length} children');
    });

    // Cancel existing children subscription
    _parentChildrenSubscription?.cancel();

    // Cancel all existing child task subscriptions
    for (var subscription in _childTaskSubscriptions.values) {
      subscription.cancel();
    }
    _childTaskSubscriptions.clear();
    // Listen to children list changes and set up/remove task listeners accordingly
    _parentChildrenSubscription = FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .snapshots()
        .listen((childrenSnapshot) {
          // ignore: avoid_print
          print(
            '📊 Parent children listener triggered - ${childrenSnapshot.docs.length} children',
          );

          // Get current child IDs
          final currentChildIds = childrenSnapshot.docs
              .map((doc) => doc.id)
              .toSet();

          // Cancel subscriptions for children that no longer exist
          final subscriptionsToRemove = <String>[];
          for (var childId in _childTaskSubscriptions.keys) {
            if (!currentChildIds.contains(childId)) {
              _childTaskSubscriptions[childId]?.cancel();
              subscriptionsToRemove.add(childId);
            }
          }
          for (var childId in _childWishlistSubscriptions.keys) {
            if (!currentChildIds.contains(childId)) {
              _childWishlistSubscriptions[childId]?.cancel();
              if (!subscriptionsToRemove.contains(childId)) {
                subscriptionsToRemove.add(childId);
              }
            }
          }
          for (var childId in subscriptionsToRemove) {
            _childTaskSubscriptions.remove(childId);
            _childWishlistSubscriptions.remove(childId);
          }

          // Set up listeners for new children
          for (var childDoc in childrenSnapshot.docs) {
            final childId = childDoc.id;
            final childData = childDoc.data();
            final childName = childData['firstName'] ?? 'Your child';

            // Only set up listener if we don't already have one for this child
            if (!_childTaskSubscriptions.containsKey(childId)) {
              _listenToChildTasks(parentId, childId, childName);
            }
            if (!_childWishlistSubscriptions.containsKey(childId)) {
              _listenToChildWishlist(parentId, childId, childName);
            }
          }
        });
    // Also set up initial listeners for existing children
    FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .get()
        .then((childrenSnapshot) {
          for (var childDoc in childrenSnapshot.docs) {
            final childId = childDoc.id;
            final childData = childDoc.data();
            final childName = childData['firstName'] ?? 'Your child';

            // Only set up listener if we don't already have one
            if (!_childTaskSubscriptions.containsKey(childId)) {
              _listenToChildTasks(parentId, childId, childName);
            }
            if (!_childWishlistSubscriptions.containsKey(childId)) {
              _listenToChildWishlist(parentId, childId, childName);
            }
          }
        });

    // ignore: avoid_print
    print(
      '✅ Parent Firestore listener active - watching for new->pending changes',
    );
  }

  void _listenToChildTasks(String parentId, String childId, String childName) {
    // Cancel existing subscription for this child if any
    _childTaskSubscriptions[childId]?.cancel();

    // Set up a listener for this child's tasks
    final subscription = FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Tasks')
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
            // ignore: avoid_print
            print(
              '📊 Parent task listener triggered for child $childId - ${snapshot.docChanges.length} changes',
            );

            // Check for status changes
            for (var docChange in snapshot.docChanges) {
              // ignore: avoid_print
              print(
                '📝 Parent task change: ${docChange.type} - ID: ${docChange.doc.id}',
              );

              if (docChange.type == DocumentChangeType.modified) {
                final newData = docChange.doc.data() as Map<String, dynamic>;
                final newStatus = (newData['status'] ?? '').toString();
                final taskId = docChange.doc.id;
                final taskKey = '${childId}_$taskId';

                final normalizedNewStatus = _normalizeStatus(newStatus);

                // Get previous status from cache BEFORE updating it
                final oldStatus = _parentTaskStatusCache[taskKey] ?? '';
                final normalizedOldStatus = oldStatus.isNotEmpty
                    ? _normalizeStatus(oldStatus)
                    : '';

                // Check if task just became "pending" (child completed it)
                final changedToPending =
                    normalizedOldStatus != 'pending' &&
                    normalizedNewStatus == 'pending' &&
                    normalizedOldStatus.isNotEmpty;

                // Also check if cache wasn't initialized but task just became pending with recent completion
                final completedDate = newData['completedDate'] as Timestamp?;
                final now = DateTime.now();
                final isRecentCompletion =
                    completedDate != null &&
                    completedDate.toDate().isAfter(
                      now.subtract(const Duration(minutes: 5)),
                    );

                final changedToPendingWithoutCache =
                    !_parentCacheInitialized &&
                    normalizedNewStatus == 'pending' &&
                    isRecentCompletion;

                // Update cache AFTER we've checked the change
                _parentTaskStatusCache[taskKey] = normalizedNewStatus;

                // ignore: avoid_print
                print(
                  '🔄 Parent task $taskKey status change: "$normalizedOldStatus" → "$normalizedNewStatus"',
                );
                // ignore: avoid_print
                print(
                  '   changedToPending: $changedToPending, changedToPendingWithoutCache: $changedToPendingWithoutCache',
                );
                // ignore: avoid_print
                print(
                  '   _lastNotifiedParentTaskId: $_lastNotifiedParentTaskId, taskKey: $taskKey',
                );

                // Notify if task changed to pending (child completed it)
                final shouldNotify =
                    (changedToPending || changedToPendingWithoutCache) &&
                    _lastNotifiedParentTaskId != taskKey;

                if (shouldNotify) {
                  // ignore: avoid_print
                  print(
                    '✅ PARENT NOTIFICATION TRIGGERED - Child completed task!',
                  );
                  final taskName = newData['taskName'] ?? 'A task';
                  final allowance = newData['allowance'] as num?;

                  // ignore: avoid_print
                  print(
                    '🎉 Task completion detected via Firestore: $taskName (ID: $taskId) by child: $childName',
                  );

                  _lastNotifiedParentTaskId = taskKey;

                  // Show local notification immediately
                  final title = 'Task completed! ✅';
                  final body =
                      '$childName completed a task, waiting for your approval';

                  // Show device notification in notification bar (always shows, even when app is in background)
                  _showParentNotification(title: title, body: body);
                }
              } else if (docChange.type == DocumentChangeType.added) {
                // Initialize new tasks in cache
                final data = docChange.doc.data() as Map<String, dynamic>;
                final rawStatus = (data['status'] ?? '').toString();
                final normalizedStatus = _normalizeStatus(rawStatus);
                final taskKey = '${childId}_${docChange.doc.id}';
                _parentTaskStatusCache[taskKey] = normalizedStatus;
                // ignore: avoid_print
                print(
                  '📋 Added new parent task $taskKey to cache: "$rawStatus" → "$normalizedStatus"',
                );
              }
            }
          },
          onError: (error) {
            // ignore: avoid_print
            print('❌ Error in parent task listener for child $childId: $error');
          },
        );

    // Store the subscription
    _childTaskSubscriptions[childId] = subscription;
  }

  void _listenToChildWishlist(
    String parentId,
    String childId,
    String childName,
  ) {
    // Cancel existing subscription for this child if any
    _childWishlistSubscriptions[childId]?.cancel();

    // First, initialize the cache with current wishlist item completion statuses
    FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Wishlist')
        .get()
        .then((wishlistSnapshot) {
          // ignore: avoid_print
          print(
            '📋 Initializing wishlist cache with ${wishlistSnapshot.docs.length} items for child $childId',
          );
          for (var doc in wishlistSnapshot.docs) {
            final data = doc.data();
            final isCompleted = _isWishlistItemCompleted(data);
            _wishlistItemCompletionCache[doc.id] = isCompleted;
            // ignore: avoid_print
            print(
              '📋 Cached wishlist item ${doc.id}: completionState=$isCompleted',
            );
          }
          // ignore: avoid_print
          print('✅ Wishlist cache initialized for child $childId');
        })
        .catchError((error) {
          // ignore: avoid_print
          print('⚠️ Error initializing wishlist cache: $error');
        });

    // Set up a listener for this child's wishlist items
    final subscription = FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Wishlist')
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
            // ignore: avoid_print
            print(
              '📊 Parent wishlist listener triggered for child $childId - ${snapshot.docChanges.length} changes',
            );

            // Check for completion status changes
            for (var docChange in snapshot.docChanges) {
              // ignore: avoid_print
              print(
                '📝 Parent wishlist change: ${docChange.type} - ID: ${docChange.doc.id}',
              );

              if (docChange.type == DocumentChangeType.modified) {
                final newData = docChange.doc.data() as Map<String, dynamic>;
                final itemId = docChange.doc.id;

                // Get field values (handle both naming conventions)
                final newIsCompleted = newData['isCompleted'] ?? false;
                final itemPrice =
                    (newData['price'] ?? newData['itemPrice'] ?? 0) as num;

                // Get previous status from cache BEFORE updating it
                final oldIsCompleted =
                    _wishlistItemCompletionCache[itemId] ?? false;

                // Update cache AFTER we've checked the change
                _wishlistItemCompletionCache[itemId] = newIsCompleted as bool;

                // ignore: avoid_print
                print(
                  '🔄 Wishlist item $itemId: isCompleted=$oldIsCompleted → $newIsCompleted, price=$itemPrice',
                );

                // Check if item just became unlocked/completed (milestone achieved)
                // This happens when the child completes tasks and earns enough to unlock the wishlist item
                final milestoneCompleted =
                    !oldIsCompleted && newIsCompleted == true;

                if (milestoneCompleted) {
                  // ignore: avoid_print
                  print(
                    '✅ WISHLIST MILESTONE NOTIFICATION TRIGGERED - Child unlocked wishlist item!',
                  );
                  final itemName =
                      newData['name'] ??
                      newData['itemName'] ??
                      'A wishlist item';

                  // ignore: avoid_print
                  print(
                    '🎉 Wishlist milestone detected via Firestore: $itemName (ID: $itemId) by child: $childName',
                  );

                  // Show device notification in notification bar
                  final title = 'Wishlist milestone achieved! 🎉';
                  final body = itemPrice > 0
                      ? '$childName unlocked "$itemName" (${itemPrice.toInt()} ﷼) - Great responsibility!'
                      : '$childName unlocked "$itemName" - Great responsibility!';

                  _showWishlistMilestoneNotification(title: title, body: body);
                }
              } else if (docChange.type == DocumentChangeType.added) {
                // Initialize new wishlist items in cache
                final data = docChange.doc.data() as Map<String, dynamic>;
                final isCompleted = data['isCompleted'] ?? false;
                _wishlistItemCompletionCache[docChange.doc.id] =
                    isCompleted as bool;
                // ignore: avoid_print
                print(
                  '📋 Added new wishlist item ${docChange.doc.id} to cache: isCompleted=$isCompleted',
                );
              }
            }
          },
          onError: (error) {
            // ignore: avoid_print
            print(
              '❌ Error in parent wishlist listener for child $childId: $error',
            );
          },
        );

    // Store the subscription
    _childWishlistSubscriptions[childId] = subscription;
  }

  bool _isWishlistItemCompleted(Map<String, dynamic> data) {
    final bool explicitCompleted = data['isCompleted'] == true;
    final String status = (data['status'] ?? data['statuss'] ?? '')
        .toString()
        .toLowerCase();
    final bool statusCompleted =
        status == 'completed' || status == 'complete' || status == 'done';
    final double targetPrice = _toDouble(
      data['price'] ?? data['itemPrice'] ?? data['cost'] ?? 0,
    );
    final double progressValue = _toDouble(
      data['progress'] ??
          data['amountSaved'] ??
          data['currentAmount'] ??
          data['balance'] ??
          0,
    );
    final bool progressCompleted =
        targetPrice > 0 && progressValue >= targetPrice;
    return explicitCompleted || statusCompleted || progressCompleted;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'task_approval_channel',
          'Task Approvals',
          channelDescription: 'Notifications when parent approves your tasks',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          playSound: true,
          enableVibration: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: 'task_approved',
    );

    // ignore: avoid_print
    print('🔔 Local notification shown: $title - $body');
  }

  Future<void> _showParentNotification({
    required String title,
    required String body,
  }) async {
    // Ensure notification always shows as system notification in notification bar
    // This will appear in the device notification bar, not just as a popup
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'task_completion_channel',
          'Task Completions',
          channelDescription: 'Notifications when your child completes a task',
          importance: Importance
              .max, // Maximum importance to always show in notification bar
          priority: Priority.high,
          showWhen: true,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          channelShowBadge: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // This creates a REAL device notification that appears in the notification bar
    // It will show even when app is in background or closed
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 +
          100000, // Different ID range for parent notifications
      title,
      body,
      details,
      payload: 'task_completed',
    );

    // ignore: avoid_print
    print(
      '🔔 Parent DEVICE notification shown in notification bar: $title - $body',
    );
  }

  Future<void> _showNewTaskNotification({
    required String title,
    required String body,
  }) async {
    // Ensure notification always shows as system notification in notification bar
    // This will appear in the device notification bar when parent assigns a new task
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'new_task_channel',
          'New Tasks',
          channelDescription:
              'Notifications when parent assigns you a new task',
          importance: Importance
              .max, // Maximum importance to always show in notification bar
          priority: Priority.high,
          showWhen: true,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          channelShowBadge: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // This creates a REAL device notification that appears in the notification bar
    // It will show even when app is in background or closed
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 +
          200000, // Different ID range for new task notifications
      title,
      body,
      details,
      payload: 'new_task_assigned',
    );

    // ignore: avoid_print
    print(
      '🔔 New task DEVICE notification shown in notification bar: $title - $body',
    );
  }

  Future<void> _showTaskRejectedNotification({
    required String title,
    required String body,
  }) async {
    // Ensure notification always shows as system notification in notification bar
    // This will appear in the device notification bar when parent declines a task
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'task_rejection_channel',
          'Task Rejections',
          channelDescription: 'Notifications when parent declines your tasks',
          importance: Importance
              .max, // Maximum importance to always show in notification bar
          priority: Priority.high,
          showWhen: true,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          channelShowBadge: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // This creates a REAL device notification that appears in the notification bar
    // It will show even when app is in background or closed
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 +
          300000, // Different ID range for rejection notifications
      title,
      body,
      details,
      payload: 'task_rejected',
    );

    // ignore: avoid_print
    print(
      '🔔 Task rejected DEVICE notification shown in notification bar: $title - $body',
    );
  }

  Future<void> _showWishlistMilestoneNotification({
    required String title,
    required String body,
  }) async {
    // Ensure notification always shows as system notification in notification bar
    // This will appear in the device notification bar when child completes a wishlist milestone
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'wishlist_milestone_channel',
          'Wishlist Milestones',
          channelDescription:
              'Notifications when your child completes a wishlist milestone',
          importance: Importance
              .max, // Maximum importance to always show in notification bar
          priority: Priority.high,
          showWhen: true,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          channelShowBadge: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // This creates a REAL device notification that appears in the notification bar
    // It will show even when app is in background or closed
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000 +
          400000, // Different ID range for wishlist notifications
      title,
      body,
      details,
      payload: 'wishlist_milestone',
    );

    // ignore: avoid_print
    print(
      '🔔 Wishlist milestone DEVICE notification shown in notification bar: $title - $body',
    );
  }

  /// Start periodic checking for overdue tasks and reminders (due today/tomorrow)
  void _startOverdueTaskChecker(String parentId, String childId) {
    // Cancel any existing timer
    _overdueTaskCheckTimer?.cancel();
    
    // Check immediately on start (with a delay to ensure initialization is complete)
    // This ensures tasks due today or tomorrow in the database are notified when app starts
    // IMPORTANT: This runs on every app start to notify about existing tasks due today/tomorrow
    Future.delayed(const Duration(seconds: 3), () async {
      // ignore: avoid_print
      print('🔍 ===== RUNNING INITIAL CHECK ON APP START =====');
      // ignore: avoid_print
      print('🔍 Checking for tasks due today, tomorrow, and overdue tasks...');
      // ignore: avoid_print
      print('🔍 This check runs when app first starts to notify about existing tasks');
      await _checkForOverdueTasks(parentId, childId);
      // ignore: avoid_print
      print('🔍 ===== INITIAL CHECK COMPLETE =====');
    });
    
    // Then check every hour (3600 seconds)
    // TODO: For testing, change to Duration(minutes: 1) or Duration(minutes: 2)
    // For production, use Duration(hours: 1)
    _overdueTaskCheckTimer = Timer.periodic(
      const Duration(minutes: 1), // TESTING: Changed to 1 minute for faster testing. Change back to hours: 1 for production
      (_) => _checkForOverdueTasks(parentId, childId),
    );
    
    // ignore: avoid_print
    print('⏰ Task checker started - will check for reminders (today/tomorrow) and overdue tasks (checks every minute - TESTING MODE)');
  }

  /// Check for overdue tasks and reminders (due today/tomorrow) and send notifications
  Future<void> _checkForOverdueTasks(String parentId, String childId) async {
    try {
      // ignore: avoid_print
      print('🔍 ===== STARTING TASK CHECK =====');
      // ignore: avoid_print
      print('🔍 Checking for tasks due today, tomorrow, and overdue tasks...');
      // ignore: avoid_print
      print('🔍 Parent ID: $parentId, Child ID: $childId');
      
      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);
      final tomorrowOnly = todayOnly.add(const Duration(days: 1));
      // ignore: avoid_print
      print('🔍 Current date: $now');
      // ignore: avoid_print
      print('🔍 Today (date only): $todayOnly');
      // ignore: avoid_print
      print('🔍 Tomorrow (date only): $tomorrowOnly');
      
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Tasks')
          .where('status', isEqualTo: 'new') // Only check 'new' status tasks
          .get();

      // ignore: avoid_print
      print('📋 Found ${tasksSnapshot.docs.length} tasks with status "new" to check');
      
      if (tasksSnapshot.docs.isEmpty) {
        // ignore: avoid_print
        print('⚠️ No tasks found with status "new". Nothing to check.');
        return;
      }

      int overdueCount = 0;
      int reminderTodayCount = 0;
      int reminderTomorrowCount = 0;
      
      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        final dueDate = data['dueDate'] as Timestamp?;
        
        if (dueDate != null) {
          final dueDateTime = dueDate.toDate();
          
            final taskId = doc.id;
            final taskName = data['taskName'] ?? 'Your task';
          
          // Check if the due date is TODAY or TOMORROW (for reminder notifications)
          // IMPORTANT: We compare only the date part (year, month, day) to determine if it's today/tomorrow
          final dueDateOnly = DateTime(dueDateTime.year, dueDateTime.month, dueDateTime.day);
          final isDueDateToday = dueDateOnly.isAtSameMomentAs(todayOnly);
          final isDueDateTomorrow = dueDateOnly.isAtSameMomentAs(tomorrowOnly);
          
          // Debug: Log date comparison details
          // ignore: avoid_print
          print('🔍 Task "$taskName" (ID: $taskId): dueDateOnly=$dueDateOnly, todayOnly=$todayOnly, tomorrowOnly=$tomorrowOnly');
          // ignore: avoid_print
          print('🔍   isDueDateToday=$isDueDateToday, isDueDateTomorrow=$isDueDateTomorrow');
          
          // Check for reminder notifications (due today or tomorrow)
          if (isDueDateToday) {
            final reminderKey = 'reminder_today_$taskId:${dueDate.seconds}:${dueDate.nanoseconds}';
            final alreadyNotified = _notifiedOverdueTasks.contains(reminderKey);
            // ignore: avoid_print
            print('📅 Task "$taskName" is due TODAY! Key: $reminderKey, Already notified: $alreadyNotified');
            
            if (!alreadyNotified) {
              _notifiedOverdueTasks.add(reminderKey);
              reminderTodayCount++;
              // ignore: avoid_print
              print('📅 ✅ Sending reminder notification for task due today: "$taskName"');
              await _showTaskReminderNotification(taskName: taskName, isDueToday: true);
            } else {
              // ignore: avoid_print
              print('⏭️ Task "$taskName" is due today but already notified (key: $reminderKey)');
            }
            continue; // Skip overdue check for tasks due today
          } else if (isDueDateTomorrow) {
            final reminderKey = 'reminder_tomorrow_$taskId:${dueDate.seconds}:${dueDate.nanoseconds}';
            final alreadyNotified = _notifiedOverdueTasks.contains(reminderKey);
            // ignore: avoid_print
            print('📅 Task "$taskName" is due TOMORROW! Key: $reminderKey, Already notified: $alreadyNotified');
            
            if (!alreadyNotified) {
              _notifiedOverdueTasks.add(reminderKey);
              reminderTomorrowCount++;
              // ignore: avoid_print
              print('📅 ✅ Sending reminder notification for task due tomorrow: "$taskName"');
              await _showTaskReminderNotification(taskName: taskName, isDueToday: false);
            } else {
              // ignore: avoid_print
              print('⏭️ Task "$taskName" is due tomorrow but already notified (key: $reminderKey)');
            }
            continue; // Skip overdue check for tasks due tomorrow
          }
          
          // Check if task is overdue (due date is BEFORE today, not today or tomorrow)
          // IMPORTANT: Compare only the date part, not the time
          final isOverdue = dueDateOnly.isBefore(todayOnly);
          
          // Check if we've already notified for this task with this dueDate
          // We use a combination of taskId and dueDate to track notifications
          // This allows re-notification if the dueDate changes
          final notificationKey = '$taskId:${dueDate.seconds}:${dueDate.nanoseconds}';
          final alreadyNotified = _notifiedOverdueTasks.contains(notificationKey);
          
          // Only notify if:
          // 1. We haven't notified about this task with this dueDate before
          // 2. The task is overdue (due date is BEFORE today, not today or tomorrow)
          if (!alreadyNotified && isOverdue) {
            final daysOverdue = todayOnly.difference(dueDateOnly).inDays;
            
            // Safety check: Ensure daysOverdue is at least 1 (should be since we excluded today)
            if (daysOverdue < 1) {
              // ignore: avoid_print
              print('⚠️ ERROR: Task $taskName has daysOverdue=$daysOverdue but should be >= 1. Skipping.');
              continue; // Skip to next task
            }
            
            final overdueText = daysOverdue == 1 
                      ? '1 day ago' 
                      : '$daysOverdue days ago';
              
              // ignore: avoid_print
            print('⚠️ Task is overdue: $taskName (due $overdueText)');
              
              _showOverdueTaskNotification(
                taskName: taskName,
                daysOverdue: daysOverdue,
              );
              
            // Mark that we've notified about this task with this dueDate (only once)
            _notifiedOverdueTasks.add(notificationKey);
              overdueCount++;
          } else if (alreadyNotified) {
            // ignore: avoid_print
            print('⏭️ Skipping overdue notification for $taskName - already notified for this dueDate');
          } else if (!isOverdue) {
            // ignore: avoid_print
            print('⏭️ Skipping overdue notification for $taskName - not overdue yet (due date: $dueDateOnly, today: $todayOnly)');
          }
        }
      }
      
      // ignore: avoid_print
      print('✅ Check complete:');
      if (reminderTodayCount > 0) {
        // ignore: avoid_print
        print('   📅 Sent $reminderTodayCount reminder notification(s) for tasks due today');
      }
      if (reminderTomorrowCount > 0) {
        // ignore: avoid_print
        print('   📅 Sent $reminderTomorrowCount reminder notification(s) for tasks due tomorrow');
      }
      if (overdueCount > 0) {
        // ignore: avoid_print
        print('   ⏰ Sent $overdueCount overdue notification(s)');
      }
      if (reminderTodayCount == 0 && reminderTomorrowCount == 0 && overdueCount == 0) {
        // ignore: avoid_print
        print('   ℹ️ No tasks due today, tomorrow, or overdue found');
      }
    } catch (error) {
      // ignore: avoid_print
      print('⚠️ Error checking for overdue tasks: $error');
    }
  }

  Future<void> _showOverdueTaskNotification({
    required String taskName,
    required int daysOverdue,
  }) async {
    // Safety check: Never show notification for tasks due today (daysOverdue should be >= 1)
    if (daysOverdue < 1) {
      // ignore: avoid_print
      print('⚠️ ERROR: Attempted to show overdue notification with daysOverdue=$daysOverdue (should be >= 1). Skipping.');
      return;
    }

    final overdueText = daysOverdue == 1
            ? '1 day ago' 
            : '$daysOverdue days ago';
    
    final title = '⏰ Task Overdue';
    final body = '$taskName was due $overdueText.';
    
    // SOLUTION B: Create a foreground service channel for showing notifications when app is open
    // This is critical for Android to show notifications even when app is in foreground
    if (Platform.isAndroid) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        // Create foreground service channel (for notifications when app is open)
        const AndroidNotificationChannel foregroundChannel = AndroidNotificationChannel(
          'foreground_service_channel',
          'Foreground Service',
          description: 'Used to show notifications while app is open',
          importance: Importance.max, // MAX importance for heads-up notifications
          playSound: true,
          showBadge: true,
          enableVibration: true,
          enableLights: true,
        );
        
        await androidImplementation.createNotificationChannel(foregroundChannel);
        // ignore: avoid_print
        print('✅ Foreground service channel created: foreground_service_channel');
        
        // Also create/verify the overdue task channel
        final AndroidNotificationChannel overdueChannel = AndroidNotificationChannel(
      'overdue_task_channel',
      'Overdue Tasks',
          description: 'Notifications when your tasks are overdue',
          importance: Importance.max, // Maximum importance for heads-up notifications
          playSound: true,
          showBadge: true,
          enableVibration: true,
          enableLights: true,
        );
        
        await androidImplementation.createNotificationChannel(overdueChannel);
        // ignore: avoid_print
        print('✅ Overdue task channel created/verified: overdue_task_channel (importance: max)');
      }
    }

    // SOLUTION B: Use foreground service channel to show notifications when app is open
    // This channel is specifically designed to show notifications even when app is in foreground
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'foreground_service_channel', // Use foreground service channel for better visibility
      'Foreground Service',
      channelDescription: 'Used to show notifications while app is open',
      importance: Importance.max, // MAX importance for heads-up notifications
      priority: Priority.max, // MAX priority for heads-up notifications
      showWhen: true,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      channelShowBadge: true,
      ongoing: false, // Not an ongoing notification
      autoCancel: true, // Allow user to dismiss
      styleInformation: BigTextStyleInformation(body), // Use big text style for better visibility
      ticker: 'Task Overdue: $taskName', // Ticker text for heads-up notification
      category: AndroidNotificationCategory.alarm, // Use alarm category for maximum visibility
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      // CRITICAL: Request notification permission AGAIN if needed (Android 13+ / iOS)
      // Permission must be granted, otherwise notification will be logged but never shown
      if (Platform.isAndroid) {
        final androidImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          // Request permission explicitly - this is required for Android 13+
          final permissionGranted = await androidImplementation.requestNotificationsPermission();
          // ignore: avoid_print
          print('🔔 Android notification permission status: $permissionGranted');
          if (permissionGranted == false) {
            // ignore: avoid_print
            print('❌ CRITICAL: Notification permission NOT granted!');
            // ignore: avoid_print
            print('❌ Go to: Settings → Apps → Haseela → Notifications → Enable');
            // ignore: avoid_print
            print('⚠️ Notification will NOT appear without permission.');
            return;
          }
          // ignore: avoid_print
          print('✅ Notification permission confirmed: GRANTED');
        }
      } else if (Platform.isIOS) {
        // iOS permission request
        final iosImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (iosImplementation != null) {
          final result = await iosImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          // ignore: avoid_print
          print('🔔 iOS notification permission status: $result');
          if (result == false) {
            // ignore: avoid_print
            print('❌ CRITICAL: iOS notification permission NOT granted!');
            return;
          }
        }
      }

      // Use a UNIQUE notification ID based on timestamp to ensure each notification is shown
      // Using milliseconds divided by 1000 to get seconds-based ID (as recommended)
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // ignore: avoid_print
      print('🔔 Attempting to show notification: ID=$notificationId, title=$title, body=$body');
      
      // IMPORTANT: Explicitly call .show() even when app is in foreground
      // Flutter Local Notifications requires explicit .show() call to display notifications
      // when the app is open - just having the listener fire is NOT enough
      try {
        // Force show notification - this MUST be called even when app is in foreground
    await _localNotifications.show(
          notificationId,
      title,
      body,
      details,
      payload: 'overdue_task',
    );
    
    // ignore: avoid_print
        print('✅ Notification .show() called successfully - ID: $notificationId');
        // ignore: avoid_print
        print('✅ This notification should appear even when app is in foreground');
      } catch (showError) {
        // ignore: avoid_print
        print('❌ ERROR calling _localNotifications.show(): $showError');
        rethrow; // Re-throw to be caught by outer try-catch
      }
      
      
      // Double-check: On Android, verify notification was posted
      if (Platform.isAndroid) {
        // Give the system a moment to process
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Verify the notification was actually posted
        final androidImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          try {
            // Check if notifications are enabled for this channel
            final activeNotifications = await androidImplementation.getActiveNotifications();
            // ignore: avoid_print
            print('🔔 Active notifications count: ${activeNotifications.length}');
            final found = activeNotifications.any((n) => n.id == notificationId);
            if (found) {
              // ignore: avoid_print
              print('✅ Notification confirmed active in system (ID: $notificationId)');
            } else {
              // ignore: avoid_print
              print('⚠️ WARNING: Notification not found in active notifications list!');
              // ignore: avoid_print
              print('⚠️ This means Android suppressed the notification (likely because app is in foreground)');
              // ignore: avoid_print
              print('⚠️ Notification will appear when app is minimized or device is locked');
            }
          } catch (e) {
            // ignore: avoid_print
            print('⚠️ Could not verify notification status: $e');
          }
        }
      }

      // ignore: avoid_print
      print('✅ Overdue task notification show() called successfully');
      // ignore: avoid_print
      print('✅ Overdue task notification shown successfully: $title - $body');
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print('❌ ERROR showing overdue task notification: $error');
      // ignore: avoid_print
      print('❌ Stack trace: $stackTrace');
    }
  }

  /// Show reminder notification for tasks due today or tomorrow
  Future<void> _showTaskReminderNotification({
    required String taskName,
    required bool isDueToday,
  }) async {
    final title = isDueToday ? '📅 Task Due Today' : '📅 Task Due Tomorrow';
    final body = isDueToday 
        ? '$taskName is due today. Don\'t forget to complete it!'
        : '$taskName is due tomorrow. Remember to complete it!';
    
    // Use the same foreground service channel setup
    if (Platform.isAndroid) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        const AndroidNotificationChannel foregroundChannel = AndroidNotificationChannel(
          'foreground_service_channel',
          'Foreground Service',
          description: 'Used to show notifications while app is open',
          importance: Importance.max,
          playSound: true,
          showBadge: true,
          enableVibration: true,
          enableLights: true,
        );
        
        await androidImplementation.createNotificationChannel(foregroundChannel);
      }
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'foreground_service_channel',
      'Foreground Service',
      channelDescription: 'Used to show notifications while app is open',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ticker: title,
      styleInformation: BigTextStyleInformation(body),
      category: AndroidNotificationCategory.reminder,
      channelShowBadge: true,
      ongoing: false,
      autoCancel: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      if (Platform.isAndroid) {
        final androidImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          final permissionGranted = await androidImplementation.requestNotificationsPermission();
          if (permissionGranted == false) {
            // ignore: avoid_print
            print('❌ Notification permission not granted for reminder');
            return;
          }
        }
      }

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        notificationId,
        title,
        body,
        details,
        payload: 'task_reminder',
      );
      // ignore: avoid_print
      print('✅ Task reminder notification shown: $title - $body');
    } catch (error) {
      // ignore: avoid_print
      print('❌ Error showing task reminder notification: $error');
    }
  }

  /// Show overdue task notification from FCM (uses foreground service channel)
  Future<void> _showOverdueTaskNotificationFromFCM({
    required String title,
    required String body,
  }) async {
    if (Platform.isAndroid) {
      // Ensure foreground service channel exists
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        const AndroidNotificationChannel foregroundChannel = AndroidNotificationChannel(
          'foreground_service_channel',
          'Foreground Service',
          description: 'Used to show notifications while app is open',
          importance: Importance.max, // MAX importance for heads-up notifications
          playSound: true,
          showBadge: true,
          enableVibration: true,
          enableLights: true,
        );
        
        await androidImplementation.createNotificationChannel(foregroundChannel);
      }
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'foreground_service_channel',
      'Foreground Service',
      channelDescription: 'Used to show notifications while app is open',
      importance: Importance.max, // Use MAX importance for heads-up notifications
      priority: Priority.max, // Use MAX priority
      showWhen: true,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ticker: title,
      styleInformation: BigTextStyleInformation(body),
      category: AndroidNotificationCategory.alarm, // Alarm category for maximum visibility
      channelShowBadge: true,
      ongoing: false,
      autoCancel: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        notificationId,
        title,
        body,
        details,
        payload: 'overdue_task',
      );
      // ignore: avoid_print
      print('✅ FCM overdue notification shown (foreground service channel): $title - $body');
    } catch (error) {
      // ignore: avoid_print
      print('❌ Error showing FCM overdue notification: $error');
    }
  }

  Future<void> _saveToken({
    required String parentId,
    required String childId,
    required String token,
  }) async {
    final path = 'Parents/$parentId/Children/$childId';
    // ignore: avoid_print
    print('💾 Attempting to save FCM token to: $path');

    final childRef = FirebaseFirestore.instance
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId);

    try {
      // First, try to get current document to see existing tokens
      final docSnapshot = await childRef.get();

      List<String> existingTokens = [];
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data['fcmTokens'] != null) {
          final tokens = data['fcmTokens'];
          if (tokens is List) {
            existingTokens = tokens.map((e) => e.toString()).toList();
          }
        }
      }

      // ignore: avoid_print
      print('💾 Existing tokens count: ${existingTokens.length}');

      // Remove old tokens if this one already exists (avoid duplicates)
      if (!existingTokens.contains(token)) {
        existingTokens.add(token);
      }

      // Save with all tokens
      await childRef.set({
        'fcmTokens': existingTokens,
        'fcmPlatform': Platform.isIOS ? 'ios' : 'android',
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Verify it was saved
      final verifyDoc = await childRef.get();
      if (verifyDoc.exists) {
        final savedData = verifyDoc.data();
        final savedTokens = savedData?['fcmTokens'] as List?;
        // ignore: avoid_print
        print(
          '✅ FCM token saved successfully! Total tokens in DB: ${savedTokens?.length ?? 0}',
        );
        // ignore: avoid_print
        print(
          '✅ Token in DB: ${savedTokens?.isNotEmpty == true ? "YES" : "NO"}',
        );
      } else {
        // ignore: avoid_print
        print('⚠️ Document does not exist after save attempt');
      }
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('❌ Failed to save FCM token to $path');
      // ignore: avoid_print
      print('❌ Error: $e');
      // ignore: avoid_print
      print('❌ Stack: $stackTrace');
      rethrow; // Let caller handle if needed
    }
  }

  // Test method to manually trigger a notification (for debugging)
  Future<void> testNotification() async {
    // ignore: avoid_print
    print('🧪 ===== TESTING NOTIFICATION =====');
    try {
      // ignore: avoid_print
      print('🧪 Step 1: Ensuring local notifications are initialized...');

      // Always try to show notification - if not initialized, it will fail gracefully
      // ignore: avoid_print
      print('🧪 Step 2: Showing test notification...');
      await _showLocalNotification(
        title: '🧪 Test Notification',
        body: 'If you see this, notifications are working!',
      );
      // ignore: avoid_print
      print('🧪 ✅ Test notification sent successfully!');
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('🧪 ❌ Test notification failed: $e');
      // ignore: avoid_print
      print('🧪 Stack: $stackTrace');

      // Try re-initializing and showing again
      try {
        // ignore: avoid_print
        print('🧪 Attempting to re-initialize and retry...');
        await _initializeLocalNotifications();
        await _showLocalNotification(
          title: '🧪 Test Notification (Retry)',
          body: 'If you see this, notifications are working!',
        );
        // ignore: avoid_print
        print('🧪 ✅ Test notification sent after re-initialization!');
      } catch (retryError) {
        // ignore: avoid_print
        print('🧪 ❌ Retry also failed: $retryError');
      }
    }
  }

  // Check if notifications are properly set up
  Future<bool> isInitialized() async {
    return _cacheInitialized && _tasksSubscription != null;
  }

  void dispose() {
    _tasksSubscription?.cancel();
    _parentTasksSubscription?.cancel();
    _parentChildrenSubscription?.cancel();

    // Cancel all child task subscriptions
    for (var subscription in _childTaskSubscriptions.values) {
      subscription.cancel();
    }
    _childTaskSubscriptions.clear();

    // Cancel all child wishlist subscriptions
    for (var subscription in _childWishlistSubscriptions.values) {
      subscription.cancel();
    }
    _childWishlistSubscriptions.clear();

    _fcmForegroundSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    
    // Cancel overdue task checker timer
    _overdueTaskCheckTimer?.cancel();
    _overdueTaskCheckTimer = null;
    
    _lastNotifiedTaskId = null;
    _lastNotifiedParentTaskId = null;
    _taskStatusCache.clear();
    _parentTaskStatusCache.clear();
    _wishlistItemCompletionCache.clear();
    _notifiedNewTasks.clear();
    _cacheInitialized = false;
    _parentCacheInitialized = false;
  }
}