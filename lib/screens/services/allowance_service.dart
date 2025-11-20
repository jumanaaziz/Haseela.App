import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/allowance_settings.dart';
import '../../models/transaction.dart' as app_transaction;

class AllowanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Save or update allowance settings for a child
  static Future<void> saveAllowanceSettings(
    String parentId,
    String childId,
    AllowanceSettings settings, {
    bool merge = true,
  }) async {
    try {
      final allowanceRef = _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('allowanceSettings')
          .doc('settings');

      if (merge) {
        // Use merge to preserve lastProcessed if it exists
        await allowanceRef.set(settings.toFirestore(), SetOptions(merge: true));
      } else {
        // Replace entire document
        await allowanceRef.set(settings.toFirestore());
      }

      print('✅ Allowance settings saved for child $childId');
    } catch (e) {
      print('❌ Error saving allowance settings: $e');
      throw Exception('Failed to save allowance settings: $e');
    }
  }

  // Get allowance settings for a child
  static Future<AllowanceSettings?> getAllowanceSettings(
    String parentId,
    String childId,
  ) async {
    try {
      final allowanceDoc = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('allowanceSettings')
          .doc('settings')
          .get();

      if (allowanceDoc.exists && allowanceDoc.data() != null) {
        return AllowanceSettings.fromFirestore(allowanceDoc);
      }
      return null;
    } catch (e) {
      print('❌ Error getting allowance settings: $e');
      return null;
    }
  }

  // Delete allowance settings for a child
  static Future<void> deleteAllowanceSettings(
    String parentId,
    String childId,
  ) async {
    try {
      await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('allowanceSettings')
          .doc('settings')
          .delete();

      print('✅ Allowance settings deleted for child $childId');
    } catch (e) {
      print('❌ Error deleting allowance settings: $e');
      throw Exception('Failed to delete allowance settings: $e');
    }
  }

  // Process immediate allowance (if today matches the selected day)
  static Future<void> processImmediateAllowance(
    String parentId,
    String childId,
    AllowanceSettings settings,
  ) async {
    try {
      final today = DateTime.now();
      final todayDayName = _getDayName(today.weekday);

      // Check if today matches the selected day
      if (settings.dayOfWeek != todayDayName || !settings.isEnabled) {
        print(
          '⏭️ Skipping immediate allowance: today is $todayDayName, selected day is ${settings.dayOfWeek}',
        );
        return;
      }

      // Check if already processed today
      if (settings.lastProcessed != null) {
        final lastProcessed = settings.lastProcessed!;
        if (lastProcessed.year == today.year &&
            lastProcessed.month == today.month &&
            lastProcessed.day == today.day) {
          print('⏭️ Allowance already processed today');
          return;
        }
      }

      // Process the allowance
      await _processAllowancePayment(parentId, childId, settings);

      // Update lastProcessed
      final updatedSettings = settings.copyWith(lastProcessed: today);
      await saveAllowanceSettings(parentId, childId, updatedSettings);

      print('✅ Immediate allowance processed for child $childId');
    } catch (e) {
      print('❌ Error processing immediate allowance: $e');
      throw Exception('Failed to process immediate allowance: $e');
    }
  }

  // Process allowance payment (add to wallet and create transaction)
  static Future<void> _processAllowancePayment(
    String parentId,
    String childId,
    AllowanceSettings settings,
  ) async {
    try {
      final walletRef = _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wallet')
          .doc('wallet001');

      // Use transaction to ensure atomicity
      await _firestore.runTransaction((transaction) async {
        // Get wallet document
        final walletDoc = await transaction.get(walletRef);
        if (!walletDoc.exists) {
          throw Exception('Wallet not found for child $childId');
        }

        // Update wallet balances using FieldValue.increment
        transaction.update(walletRef, {
          'totalBalance': FieldValue.increment(settings.weeklyAmount),
          'spendingBalance': FieldValue.increment(settings.weeklyAmount),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Create transaction record
        final transactionId = DateTime.now().millisecondsSinceEpoch.toString();
        final transactionRef = _firestore
            .collection('Parents')
            .doc(parentId)
            .collection('Children')
            .doc(childId)
            .collection('Transactions')
            .doc(transactionId);

        final allowanceTransaction = app_transaction.Transaction(
          id: transactionId,
          userId: childId,
          walletId: 'wallet001',
          type: 'deposit',
          category: 'weekly_allowance',
          amount: settings.weeklyAmount,
          description: 'Weekly Allowance - ${settings.dayOfWeek}',
          date: DateTime.now(),
          fromWallet: 'total',
          toWallet: 'spending',
        );

        transaction.set(transactionRef, allowanceTransaction.toMap());
      });

      print('✅ Allowance payment processed: ${settings.weeklyAmount} SAR');
    } catch (e) {
      print('❌ Error processing allowance payment: $e');
      throw Exception('Failed to process allowance payment: $e');
    }
  }

  // Helper: Convert weekday number to day name
  static String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.sunday:
        return 'Sunday';
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      default:
        return 'Sunday';
    }
  }

  // Get all children with allowance settings (for Cloud Function)
  static Stream<QuerySnapshot> getAllChildrenWithAllowances() {
    return _firestore
        .collectionGroup('allowanceSettings')
        .where('isEnabled', isEqualTo: true)
        .snapshots();
  }
}
