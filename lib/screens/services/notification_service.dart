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
  bool _cacheInitialized = false; // Track if cache has been initialized
  bool _parentCacheInitialized =
      false; // Track if parent cache has been initialized
  bool _firstSnapshotReceived =
      false; // Track if first snapshot from listener has been received

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
        if (notif != null) {
          // ignore: avoid_print
          print('📩 FCM (foreground): ${notif.title} - ${notif.body}');
          _showLocalNotification(
            title: notif.title ?? 'Notification',
            body: notif.body ?? '',
          );
        }
      });

      // Step 6: ✅ PRIMARY METHOD: Listen to Firestore task changes directly
      // This works even if FCM fails - detects changes immediately
      // ignore: avoid_print
      print('📱 Step 6: Setting up Firestore task listener...');
      _listenToTaskChanges(parentId, childId);

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
    _cacheInitialized = false; // Reset initialization flag
    _firstSnapshotReceived = false; // Reset first snapshot flag

    // First, initialize the cache with current task statuses
    // This prevents false notifications on initial load
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
            // ignore: avoid_print
            print(
              '📋 Cached task ${doc.id}: "$rawStatus" → "$normalizedStatus"',
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
            print(
              '📊 Firestore task listener triggered - ${snapshot.docChanges.length} changes (cacheInitialized: $_cacheInitialized, firstSnapshotReceived: $_firstSnapshotReceived)',
            );
            // ignore: avoid_print
            print(
              '   Snapshot metadata: hasPendingWrites=${snapshot.metadata.hasPendingWrites}, isFromCache=${snapshot.metadata.isFromCache}',
            );

            // IMPORTANT: Track if this is the first snapshot BEFORE processing changes
            // This way, we can distinguish between initial load (first snapshot) and truly new tasks
            final isFirstSnapshot = !_firstSnapshotReceived;

            // ignore: avoid_print
            print(
              '📊 Processing snapshot: isFirstSnapshot=$isFirstSnapshot, _firstSnapshotReceived=$_firstSnapshotReceived, changes=${snapshot.docChanges.length}',
            );

            // If cache not initialized yet, we'll still process but be more careful about notifications
            // This prevents missing changes that happen during initialization

            // Check for status changes
            for (var docChange in snapshot.docChanges) {
              // ignore: avoid_print
              print(
                '📝 Task change: ${docChange.type} - ID: ${docChange.doc.id}',
              );

              if (docChange.type == DocumentChangeType.modified) {
                final newData = docChange.doc.data() as Map<String, dynamic>;
                final newStatus = (newData['status'] ?? '').toString();
                final taskId = docChange.doc.id;

                final normalizedNewStatus = _normalizeStatus(newStatus);

                // Get previous status from cache BEFORE updating it
                final oldStatus = _taskStatusCache[taskId] ?? '';
                final normalizedOldStatus = oldStatus.isNotEmpty
                    ? _normalizeStatus(oldStatus)
                    : '';

                // If cache wasn't initialized, we need to be smarter - check if this is a real change
                // by looking at completedDate timestamp - if it's very recent, it's likely a new completion
                final completedDate = newData['completedDate'] as Timestamp?;
                final now = DateTime.now();
                final isRecentCompletion =
                    completedDate != null &&
                    completedDate.toDate().isAfter(
                      now.subtract(const Duration(minutes: 5)),
                    );

                // ignore: avoid_print
                print(
                  '🔄 Task $taskId status change: "$normalizedOldStatus" → "$normalizedNewStatus"',
                );
                // ignore: avoid_print
                print('   Raw values: "$oldStatus" → "$newStatus"');
                // ignore: avoid_print
                print(
                  '   Cache initialized: $_cacheInitialized, isRecentCompletion: $isRecentCompletion',
                );

                // Update cache AFTER we've checked the change
                _taskStatusCache[taskId] = normalizedNewStatus;

                // Check if status changed from "pending" to "done"
                final isPendingToDone =
                    normalizedOldStatus == 'pending' &&
                    normalizedNewStatus == 'done';

                // Check if status changed from "pending" to "rejected" (parent declined)
                final isPendingToRejected =
                    normalizedOldStatus == 'pending' &&
                    normalizedNewStatus == 'rejected';

                // Check if status changed from anything NOT 'done' to 'done'
                // This catches pending->done, rejected->done, or any other->done transitions
                final changedToDone =
                    normalizedOldStatus != 'done' &&
                    normalizedNewStatus == 'done' &&
                    normalizedOldStatus.isNotEmpty;

                // Check if status changed to rejected (parent declined)
                final changedToRejected =
                    normalizedOldStatus != 'rejected' &&
                    normalizedNewStatus == 'rejected' &&
                    normalizedOldStatus.isNotEmpty;

                // If cache wasn't initialized but task just became done with recent completion, notify
                // This handles the case where a task changes during cache initialization
                final changedToDoneWithoutCache =
                    !_cacheInitialized &&
                    normalizedNewStatus == 'done' &&
                    isRecentCompletion;

                // ALTERNATIVE: Check if task just became "done" and has a recent completedDate
                // This catches cases where cache might not have the correct old status
                final wasJustCompleted =
                    normalizedNewStatus == 'done' &&
                    completedDate != null &&
                    completedDate.toDate().isAfter(
                      now.subtract(const Duration(minutes: 30)),
                    );

                // Also check: if oldStatus is empty (cache miss) but status is done with recent timestamp
                // This means we missed the initial status, but the task was just completed
                final isNewDoneTask =
                    normalizedOldStatus.isEmpty &&
                    normalizedNewStatus == 'done' &&
                    completedDate != null &&
                    completedDate.toDate().isAfter(
                      now.subtract(const Duration(minutes: 30)),
                    );

                // ignore: avoid_print
                print('🔍 isPendingToDone: $isPendingToDone');
                // ignore: avoid_print
                print('🔍 isPendingToRejected: $isPendingToRejected');
                // ignore: avoid_print
                print(
                  '🔍 changedToDone: $changedToDone (from "$normalizedOldStatus" to "$normalizedNewStatus")',
                );
                // ignore: avoid_print
                print(
                  '🔍 changedToRejected: $changedToRejected (from "$normalizedOldStatus" to "$normalizedNewStatus")',
                );
                // ignore: avoid_print
                print(
                  '🔍 changedToDoneWithoutCache: $changedToDoneWithoutCache',
                );
                // ignore: avoid_print
                print('🔍 wasJustCompleted: $wasJustCompleted');
                // ignore: avoid_print
                print('🔍 isNewDoneTask: $isNewDoneTask');
                // ignore: avoid_print
                print(
                  '   completedDate: $completedDate (${completedDate?.toDate()}), now: $now',
                );
                // ignore: avoid_print
                print(
                  '   _lastNotifiedTaskId: $_lastNotifiedTaskId, taskId: $taskId',
                );

                // Notify if: (pending→done) OR (anything→done) OR (changed to done without cache but recent) OR (just became done with recent timestamp and wasn't already done) OR (new done task)
                final shouldNotifyApproval =
                    (isPendingToDone ||
                        changedToDone ||
                        changedToDoneWithoutCache ||
                        (wasJustCompleted && normalizedOldStatus != 'done') ||
                        isNewDoneTask) &&
                    _lastNotifiedTaskId != taskId;

                // Notify if task was rejected (parent declined)
                final shouldNotifyRejection =
                    (isPendingToRejected || changedToRejected) &&
                    _lastNotifiedTaskId != taskId;

                // ignore: avoid_print
                print('🔔 shouldNotifyApproval: $shouldNotifyApproval');
                // ignore: avoid_print
                print('🔔 shouldNotifyRejection: $shouldNotifyRejection');
                // ignore: avoid_print
                print(
                  '   Breakdown: isPendingToDone=$isPendingToDone, isPendingToRejected=$isPendingToRejected, changedToDone=$changedToDone, changedToRejected=$changedToRejected, changedToDoneWithoutCache=$changedToDoneWithoutCache, wasJustCompleted=$wasJustCompleted (oldStatus != done: ${normalizedOldStatus != 'done'}), isNewDoneTask=$isNewDoneTask, notAlreadyNotified=${_lastNotifiedTaskId != taskId}',
                );

                if (shouldNotifyApproval) {
                  // ignore: avoid_print
                  print('✅ NOTIFICATION TRIGGERED - Task approved!');
                  final taskName = newData['taskName'] ?? 'Your task';
                  final allowance = newData['allowance'] as num?;

                  // ignore: avoid_print
                  print(
                    '🎉 Task approved detected via Firestore: $taskName (ID: $taskId)',
                  );

                  _lastNotifiedTaskId = taskId;

                  // Show device notification in notification bar
                  final title = 'Task approved! 🎉';
                  final body = allowance != null
                      ? '$taskName approved • +${allowance.toInt()} ﷼'
                      : '$taskName was approved';

                  _showLocalNotification(title: title, body: body);
                } else if (shouldNotifyRejection) {
                  // ignore: avoid_print
                  print('✅ NOTIFICATION TRIGGERED - Task rejected!');
                  final taskName = newData['taskName'] ?? 'Your task';

                  // ignore: avoid_print
                  print(
                    '⚠️ Task rejected detected via Firestore: $taskName (ID: $taskId)',
                  );

                  _lastNotifiedTaskId = taskId;

                  // Show device notification in notification bar
                  final title = 'Task declined ⚠️';
                  final body =
                      '$taskName was declined. Please review and try again.';

                  _showTaskRejectedNotification(title: title, body: body);
                }
              } else if (docChange.type == DocumentChangeType.added) {
                // New task added by parent
                final taskId = docChange.doc.id;
                final data = docChange.doc.data() as Map<String, dynamic>;
                final rawStatus = (data['status'] ?? '').toString();
                final normalizedStatus = _normalizeStatus(rawStatus);

                // Initialize new tasks in cache
                _taskStatusCache[taskId] = normalizedStatus;
                // ignore: avoid_print
                print(
                  '📋 Added new task $taskId to cache: "$rawStatus" → "$normalizedStatus"',
                );

                // IMPORTANT: If we get a DocumentChangeType.added event, it means this is a NEW document
                // that was just added to Firestore. So if the status is "new", it's definitely a new assignment.
                //
                // Strategy:
                // - After first snapshot: Any "added" event with status "new" is a new assignment → notify
                // - During first snapshot: Only notify if task was created very recently (within 2 minutes)
                //   This handles edge cases where tasks are added during listener initialization
                //
                // Notify if:
                // 1. This is a "new" task (not already done/pending/rejected)
                // 2. We haven't already notified about this task
                // 3. Either:
                //    - This is NOT the first snapshot (normal case), OR
                //    - Task was created very recently (within 2 min) - handles race condition
                final createdAt = data['createdAt'] as Timestamp?;
                final now = DateTime.now();
                final isVeryRecentlyCreated =
                    createdAt != null &&
                    createdAt.toDate().isAfter(
                      now.subtract(const Duration(minutes: 2)),
                    );

                final shouldNotifyNewTask =
                    normalizedStatus == 'new' &&
                    !_notifiedNewTasks.contains(taskId) &&
                    (!isFirstSnapshot || isVeryRecentlyCreated);

                // ignore: avoid_print
                print('🔍 New task notification check:');
                // ignore: avoid_print
                print('   Task ID: $taskId');
                // ignore: avoid_print
                print('   normalizedStatus: "$normalizedStatus"');
                // ignore: avoid_print
                print(
                  '   already notified: ${_notifiedNewTasks.contains(taskId)}',
                );
                // ignore: avoid_print
                print('   isFirstSnapshot: $isFirstSnapshot');
                // ignore: avoid_print
                print('   first snapshot received: $_firstSnapshotReceived');
                // ignore: avoid_print
                print('   cache initialized: $_cacheInitialized');
                // ignore: avoid_print
                print('   createdAt: $createdAt');
                // ignore: avoid_print
                print('   isVeryRecentlyCreated: $isVeryRecentlyCreated');
                // ignore: avoid_print
                print('   shouldNotifyNewTask: $shouldNotifyNewTask');

                if (shouldNotifyNewTask) {
                  final taskName = data['taskName'] ?? 'A new task';
                  final allowance = data['allowance'] as num?;

                  // ignore: avoid_print
                  print(
                    '✅✅✅ NEW TASK NOTIFICATION TRIGGERED - Task: $taskName (ID: $taskId)',
                  );

                  // Mark as notified
                  _notifiedNewTasks.add(taskId);

                  // Show device notification in notification bar
                  final title = 'New task assigned! 📋';
                  final body = allowance != null
                      ? '$taskName • +${allowance.toInt()} ﷼'
                      : '$taskName';

                  _showNewTaskNotification(title: title, body: body);
                } else {
                  // ignore: avoid_print
                  print(
                    '⚠️ New task notification NOT triggered - check conditions above',
                  );
                }
              }
            }

            // Mark first snapshot as received AFTER processing all changes
            // This ensures we don't notify for initial load documents
            if (isFirstSnapshot) {
              // ignore: avoid_print
              print(
                '📋 First snapshot processed - future "added" events will trigger notifications',
              );
              _firstSnapshotReceived = true;
              // Also mark cache as initialized if we have docs
              if (snapshot.docs.isNotEmpty) {
                _cacheInitialized = true;
              }
            } else {
              // ignore: avoid_print
              print(
                '📋 Subsequent snapshot processed - new tasks will trigger notifications',
              );
            }
          },
          onError: (error) {
            // ignore: avoid_print
            print('❌ Error in task listener: $error');
          },
        );

    // ignore: avoid_print
    print('✅ Firestore listener active - watching for pending->done changes');
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
          print(
            '📋 Initializing parent cache with ${childrenSnapshot.docs.length} children',
          );

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
              // ignore: avoid_print
              print(
                '📋 Cached parent task $taskKey: "$rawStatus" → "$normalizedStatus"',
              );
              totalTasks++;
            }
          }
          // ignore: avoid_print
          print(
            '✅ Parent cache initialized with $totalTasks tasks. Now listening for changes...',
          );
          _parentCacheInitialized = true; // Mark cache as ready
          // ignore: avoid_print
          print('✅ Parent cache initialization flag set to true');
        })
        .catchError((error) {
          // ignore: avoid_print
          print('⚠️ Error initializing parent cache: $error');
          _parentCacheInitialized =
              true; // Mark as initialized even on error to allow listener to work
          // ignore: avoid_print
          print(
            '⚠️ Parent cache initialization flag set to true despite error (allowing listener to work)',
          );
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
