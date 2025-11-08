import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'splash/splash_screen.dart';
import 'splash/launch_screen_old.dart';
import 'parent/parent_profile_screen.dart';
import 'child/child_home_screen.dart';
import 'child_main_wrapper.dart';

// ✅ Simple Session Service to store role + IDs globally
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  String? role;
  String? parentId;
  String? childId;

  void clear() {
    role = null;
    parentId = null;
    childId = null;
  }
}

final session = SessionService();

/// Handles authentication state and navigation after login
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print('AuthWrapper: Connection state: ${snapshot.connectionState}');
        print('AuthWrapper: Has data: ${snapshot.hasData}');
        print('AuthWrapper: Has error: ${snapshot.hasError}');

        // 1️⃣ Still checking → Splash screen
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // 2️⃣ If error → Launch screen
        if (snapshot.hasError) {
          session.clear();
          return const LaunchScreenOld();
        }

        // 3️⃣ If user is authenticated → Check role in Firestore
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          print(
            'AuthWrapper: User authenticated. Checking role for ${user.uid}',
          );

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('Users')
                .doc(user.uid)
                .get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const SplashScreen();
              }

              if (userSnapshot.hasError ||
                  !userSnapshot.hasData ||
                  !userSnapshot.data!.exists) {
                print('AuthWrapper: Error fetching role or user doc missing');
                session.clear();
                return const LaunchScreenOld();
              }

              final data = userSnapshot.data!.data() as Map<String, dynamic>;
              final role = data['role'] as String?;
              print('AuthWrapper: Role = $role');

              if (role == 'parent') {
                // ✅ Store role globally
                session.role = 'parent';
                session.parentId = user.uid;
                session.childId = null;

                return const ParentProfileScreen();
              } else if (role == 'child') {
                final parentId = data['parentId'];
                final childId = data['childId'];

                session.role = 'child';
                session.parentId = parentId;
                session.childId = childId;

                // ⬇️ send child to the *wrapper*, not HomeScreen
                return ChildMainWrapper(parentId: parentId, childId: childId);
              } else {
                print('AuthWrapper: Unknown role, redirecting to LaunchScreen');
                session.clear();
                return const LaunchScreenOld();
              }
            },
          );
        }

        // 4️⃣ If not authenticated → Launch screen (login/signup)
        print('AuthWrapper: No user, showing LaunchScreen');
        session.clear();
        return const LaunchScreenOld();
      },
    );
  }
}
