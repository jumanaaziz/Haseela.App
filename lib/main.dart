import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'screens/auth_wrapper.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'utils/app_keys.dart';

// Initialize local notifications plugin for background handler
final FlutterLocalNotificationsPlugin _backgroundNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // ignore: avoid_print
  print('🔕 FCM (background): ${message.messageId}');
  // ignore: avoid_print
  print('🔕 Message data: ${message.data}');
  // ignore: avoid_print
  print('🔕 Notification: ${message.notification?.title} - ${message.notification?.body}');
  
  // Initialize local notifications in background isolate
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  
  await _backgroundNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // ignore: avoid_print
      print('📲 Background notification tapped: ${response.payload}');
    },
  );
  
  // Create notification channel for Android if not exists
  if (Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'task_approval_channel',
      'Task Approvals',
      description: 'Notifications when parent approves your tasks',
      importance: Importance.high,
      playSound: true,
    );
    
    await _backgroundNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
  
  // If the message has a notification payload, show it
  // (The OS usually handles this automatically, but we'll show it manually as backup)
  if (message.notification != null) {
    // Determine notification channel based on message type
    final messageType = message.data['type'] ?? 'task_approval';
    final isOverdueTask = messageType == 'overdue_task';
    
    // Create notification channel for Android if not exists
    if (Platform.isAndroid && isOverdueTask) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'overdue_task_channel',
        'Overdue Tasks',
        description: 'Notifications when your tasks are overdue',
        importance: Importance.high,
        playSound: true,
      );
      
      await _backgroundNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    
    // Use appropriate channel based on message type
    final channelId = isOverdueTask ? 'overdue_task_channel' : 'task_approval_channel';
    final channelName = isOverdueTask ? 'Overdue Tasks' : 'Task Approvals';
    final channelDescription = isOverdueTask
        ? 'Notifications when your tasks are overdue'
        : 'Notifications when parent approves your tasks';
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
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
    
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _backgroundNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? 'Notification',
      message.notification?.body ?? '',
      details,
    );
    
    // ignore: avoid_print
    print('🔔 Background notification shown: ${message.notification?.title} - ${message.notification?.body}');
  }
  
  // Also handle data-only messages
  if (message.data.isNotEmpty && message.notification == null) {
    final title = message.data['title'] ?? 'Task approved! 🎉';
    final body = message.data['body'] ?? 'Your task has been approved';
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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
    
    await _backgroundNotificationsPlugin.show(
      message.hashCode,
      title,
      body,
      details,
    );
    
    // ignore: avoid_print
    print('🔔 Background data notification shown: $title - $body');
  }
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Register background handler for automatic notifications when app is closed/backgrounded
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // iPhone X as base
      minTextAdapt: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily:
                'SPProText', // ✅ this makes SP Pro Text the default font
          ),
          scaffoldMessengerKey: AppKeys.scaffoldMessengerKey,
          home: const AuthWrapper(),
        );
      },
    );
  }
}
