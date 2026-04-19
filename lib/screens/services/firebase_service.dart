import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../models/user_profile.dart';
import '../../models/wallet.dart';
import '../../models/transaction.dart' as app_transaction;
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collections
  static const String _usersCollection = 'users';
  static const String _parentsCollection = 'Parents';
  static const String _childrenSubcollection = 'Children';
  static const String _walletSubcollection = 'Wallet';
  static const String _transactionsSubcollection = 'Transactions';
  static const String _defaultChildWalletDocId = 'wallet001';

  /// Firestore path: Parents/{parentId}/Children/{childId}/Wallet/wallet001
  static DocumentReference<Map<String, dynamic>> _childWalletDocument(
    String parentId,
    String childId,
  ) {
    return _firestore
        .collection(_parentsCollection)
        .doc(parentId)
        .collection(_childrenSubcollection)
        .doc(childId)
        .collection(_walletSubcollection)
        .doc(_defaultChildWalletDocId);
  }

  // User Profile Methods
  static Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get();

      if (doc.exists) {
        return UserProfile.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  static Future<bool> createUserProfile(UserProfile profile) async {
    try {
      await _firestore
          .collection(_usersCollection)
          .doc(profile.id)
          .set(profile.toMap());
      return true;
    } catch (e) {
      print('Error creating user profile: $e');
      return false;
    }
  }

  static Future<bool> updateUserProfile(UserProfile profile) async {
    try {
      final updatedProfile = profile.copyWith(updatedAt: DateTime.now());
      await _firestore
          .collection(_usersCollection)
          .doc(profile.id)
          .update(updatedProfile.toMap());
      return true;
    } catch (e) {
      print('Error updating user profile: $e');
      return false;
    }
  }

  static Future<bool> updateUserPhoneNumber(
    String userId,
    String phoneNumber,
  ) async {
    try {
      await _firestore.collection(_usersCollection).doc(userId).update({
        'phoneNumber': phoneNumber,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error updating phone number: $e');
      return false;
    }
  }

  static Future<bool> updateUserProfileImage(
    String userId,
    String imageUrl,
  ) async {
    try {
      await _firestore.collection(_usersCollection).doc(userId).update({
        'profileImageUrl': imageUrl,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error updating profile image: $e');
      return false;
    }
  }

  // Wallet Methods (Child-specific)
  static Future<Wallet?> getChildWallet(String parentId, String childId) async {
    try {
      print('Getting wallet for parent: $parentId, child: $childId');

      final doc = await _childWalletDocument(parentId, childId).get();

      print('Document exists: ${doc.exists}');
      if (doc.exists) {
        print('Document data: ${doc.data()}');
        return Wallet.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error getting child wallet: $e');
      return null;
    }
  }

  static Future<bool> createChildWallet(
    String parentId,
    String childId,
    Wallet wallet,
  ) async {
    try {
      print('Creating wallet for parent: $parentId, child: $childId');
      print('Wallet data: ${wallet.toMap()}');

      await _childWalletDocument(parentId, childId).set(wallet.toMap());

      print('Wallet created successfully');
      return true;
    } catch (e) {
      print('Error creating child wallet: $e');
      return false;
    }
  }

  static Future<bool> updateChildWalletBalance(
    String parentId,
    String childId, {
    double? totalBalance,
    double? spendingBalance,
    double? savingBalance,
    double? savingGoal,
  }) async {
    try {
      Map<String, dynamic> updateData = {
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (totalBalance != null) {
        updateData['totalBalance'] = totalBalance;
      }
      if (spendingBalance != null) {
        updateData['spendingBalance'] = spendingBalance;
      }
      if (savingBalance != null) {
        updateData['savingBalance'] = savingBalance;
      }
      if (savingGoal != null) {
        updateData['savingGoal'] =
            savingGoal; // Updated to match your database field name
      }

      await _childWalletDocument(parentId, childId).update(updateData);

      return true;
    } catch (e) {
      print('Error updating child wallet balance: $e');
      return false;
    }
  }

  static Future<bool> updateChildWallet(
    String parentId,
    String childId,
    Wallet wallet,
  ) async {
    try {
      final updatedWallet = wallet.copyWith(updatedAt: DateTime.now());
      await _childWalletDocument(parentId, childId).update(updatedWallet.toMap());
      return true;
    } catch (e) {
      print('Error updating child wallet: $e');
      return false;
    }
  }

  // Stream methods for real-time updates
  static Stream<UserProfile?> getUserProfileStream(String userId) {
    return _firestore.collection(_usersCollection).doc(userId).snapshots().map((
      doc,
    ) {
      if (doc.exists) {
        return UserProfile.fromMap(doc.data()!);
      }
      return null;
    });
  }

  static Stream<Wallet?> getChildWalletStream(String parentId, String childId) {
    return _childWalletDocument(parentId, childId)
        .snapshots()
        .map((doc) {
          if (doc.exists) {
            return Wallet.fromMap(doc.data()!);
          }
          return null;
        });
  }

  static Stream<List<app_transaction.Transaction>>
  getChildWalletTransactionsStream(
    String parentId,
    String childId,
    String walletType,
  ) {
    return _firestore
        .collection(_parentsCollection)
        .doc(parentId)
        .collection(_childrenSubcollection)
        .doc(childId)
        .collection(_transactionsSubcollection)
        .snapshots()
        .map((snapshot) {
          final transactions = <app_transaction.Transaction>[];

          for (final doc in snapshot.docs) {
            final transaction = app_transaction.Transaction.fromMap(doc.data());
            // Include transactions where this wallet is either source or destination
            if (transaction.fromWallet == walletType ||
                transaction.toWallet == walletType) {
              transactions.add(transaction);
            }
          }

          // Sort by date descending
          transactions.sort((a, b) => b.date.compareTo(a.date));

          print(
            'Stream: Found ${transactions.length} transactions for $walletType wallet',
          );
          return transactions;
        });
  }

  // Transaction Methods (Child-specific)
  static Future<bool> createChildTransaction(
    String parentId,
    String childId,
    app_transaction.Transaction transaction,
  ) async {
    try {
      await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .collection(_transactionsSubcollection)
          .doc(transaction.id)
          .set(transaction.toMap());
      return true;
    } catch (e) {
      print('Error creating child transaction: $e');
      return false;
    }
  }

  static Future<List<app_transaction.Transaction>> getChildTransactions(
    String parentId,
    String childId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .collection(_transactionsSubcollection)
          .orderBy('date', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => app_transaction.Transaction.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error getting child transactions: $e');
      return [];
    }
  }

  static Future<List<app_transaction.Transaction>> getChildWalletTransactions(
    String parentId,
    String childId,
    String walletType,
  ) async {
    try {
      print(
        'Getting transactions for parent: $parentId, child: $childId, wallet: $walletType',
      );

      // Get transactions where this wallet is either the source or destination
      final querySnapshot = await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .collection(_transactionsSubcollection)
          .where('fromWallet', isEqualTo: walletType)
          .orderBy('date', descending: true)
          .get();

      final toWalletQuerySnapshot = await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .collection(_transactionsSubcollection)
          .where('toWallet', isEqualTo: walletType)
          .orderBy('date', descending: true)
          .get();

      print('From wallet query: ${querySnapshot.docs.length} docs');
      print('To wallet query: ${toWalletQuerySnapshot.docs.length} docs');

      // Combine both queries and remove duplicates
      final allTransactions = <app_transaction.Transaction>[];
      final transactionIds = <String>{};

      // Add transactions where this wallet is the source
      for (final doc in querySnapshot.docs) {
        final transaction = app_transaction.Transaction.fromMap(doc.data());
        print(
          'From wallet transaction: ${transaction.id} - ${transaction.fromWallet} -> ${transaction.toWallet}',
        );
        if (!transactionIds.contains(transaction.id)) {
          allTransactions.add(transaction);
          transactionIds.add(transaction.id);
        }
      }

      // Add transactions where this wallet is the destination
      for (final doc in toWalletQuerySnapshot.docs) {
        final transaction = app_transaction.Transaction.fromMap(doc.data());
        print(
          'To wallet transaction: ${transaction.id} - ${transaction.fromWallet} -> ${transaction.toWallet}',
        );
        if (!transactionIds.contains(transaction.id)) {
          allTransactions.add(transaction);
          transactionIds.add(transaction.id);
        }
      }

      // Sort by date descending
      allTransactions.sort((a, b) => b.date.compareTo(a.date));

      print(
        'Found ${allTransactions.length} transactions for $walletType wallet',
      );
      return allTransactions;
    } catch (e) {
      print('Error getting child wallet transactions: $e');
      return [];
    }
  }

  // Test method to verify Firebase connection and data structure
  static Future<void> testFirebaseConnection(
    String parentId,
    String childId,
  ) async {
    try {
      print('=== Testing Firebase Connection ===');

      // Test wallet access
      final wallet = await getChildWallet(parentId, childId);
      print('Wallet found: ${wallet != null}');
      if (wallet != null) {
        print('Wallet data: ${wallet.toMap()}');
      }

      // Test transactions collection access
      final transactionsSnapshot = await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .collection(_transactionsSubcollection)
          .get();

      print(
        'Total transactions in collection: ${transactionsSnapshot.docs.length}',
      );

      for (final doc in transactionsSnapshot.docs) {
        print('Transaction ${doc.id}: ${doc.data()}');
      }

      print('=== Firebase Test Complete ===');
    } catch (e) {
      print('Firebase test error: $e');
    }
  }

  // Avatar Storage Methods
  static Future<String?> uploadAvatar(
    String parentId,
    String childId,
    File imageFile,
  ) async {
    try {
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage
          .ref()
          .child('avatars')
          .child(parentId)
          .child(childId)
          .child(fileName);

      final uploadTask = await ref.putFile(imageFile);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      print('Avatar uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('Error uploading avatar: $e');
      return null;
    }
  }

  static Future<bool> updateChildAvatar(
    String parentId,
    String childId,
    String avatarUrl,
  ) async {
    try {
      print('=== UPDATE CHILD AVATAR DEBUG ===');
      print('Parent ID: $parentId');
      print('Child ID: $childId');
      print('Avatar URL: $avatarUrl');

      await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .update({'avatar': avatarUrl});

      print('Avatar update successful');
      return true;
    } catch (e) {
      print('Error updating child avatar: $e');
      return false;
    }
  }

  // Child Profile Methods
  static Future<bool> updateChildProfile(
    String parentId,
    String childId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .update(profileData);
      return true;
    } catch (e) {
      print('Error updating child profile: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getChildProfile(
    String parentId,
    String childId,
  ) async {
    try {
      final doc = await _firestore
          .collection(_parentsCollection)
          .doc(parentId)
          .collection(_childrenSubcollection)
          .doc(childId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('Error getting child profile: $e');
      return null;
    }
  }

  // Initialize default data for new child
  static Future<bool> initializeChildData(
    String parentId,
    String childId,
  ) async {
    try {
      // Create default wallet for child with zero balances
      final wallet = Wallet(
        id: _defaultChildWalletDocId,
        userId: childId,
        totalBalance: 0.0,
        spendingBalance: 0.0,
        savingBalance: 0.0,
        savingGoal: 100.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await createChildWallet(parentId, childId, wallet);
      return true;
    } catch (e) {
      print('Error initializing child data: $e');
      return false;
    }
  }
}

Future<String?> createChildAuthAccount(String email, String password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);

    return userCredential
        .user
        ?.uid; // store this uid in the Firestore child doc
  } on FirebaseAuthException catch (e) {
    print('Error creating child account: $e');
    return null;
  }
}
