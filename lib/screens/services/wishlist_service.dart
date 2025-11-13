import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/wishlist_item.dart';

class WishlistService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Set<String> _processingPurchaseAdjustments = {};

  // Get all wishlist items for a child
  static Stream<List<WishlistItem>> getWishlistItems(
    String parentId,
    String childId,
  ) {
    print(
      '🔍 WishlistService: Getting wishlist items for parentId: $parentId, childId: $childId',
    );

    try {
      return _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .snapshots()
          .map((snapshot) {
            print('📊 WishlistService: Received ${snapshot.docs.length} items');

            if (snapshot.docs.isEmpty) {
              print('📊 WishlistService: No items found, returning empty list');
              return <WishlistItem>[];
            }

            List<WishlistItem> items = [];
            for (var doc in snapshot.docs) {
              try {
                final item = WishlistItem.fromFirestore(doc);
                items.add(item);
                print(
                  '✅ WishlistService: Successfully parsed item: ${item.name}',
                );
              } catch (e) {
                print(
                  '❌ WishlistService: Error parsing document ${doc.id}: $e',
                );
                print('❌ Document data: ${doc.data()}');
                // Continue with other items instead of failing completely
              }
            }

            // Sort by creation date manually
            items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            for (final item in items) {
              _handleAutomaticPurchaseAdjustment(
                parentId,
                childId,
                item,
              );
            }

            return items;
          });
    } catch (e) {
      print('❌ WishlistService: Error setting up stream: $e');
      return Stream.error(e);
    }
  }

  // Add a new wishlist item
  static Future<String> addWishlistItem(
    String parentId,
    String childId,
    String name,
    double price,
    String description,
  ) async {
    try {
      print(
        '🔍 WishlistService: Adding item - parentId: $parentId, childId: $childId',
      );
      print('🔍 WishlistService: Item details - name: $name, price: $price');

      final now = DateTime.now();
      final collectionPath = 'Parents/$parentId/Children/$childId/Wishlist';
      print('🔍 WishlistService: Collection path: $collectionPath');

      final docRef = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .add({
            'name': name,
            'price': price,
            'description': description,
            'createdAt': Timestamp.fromDate(now),
            'updatedAt': Timestamp.fromDate(now),
            'isCompleted': false,
            'isPurchased': false,
            'purchaseDeducted': false,
          });

      print('✅ WishlistService: Successfully added item with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ WishlistService: Error adding item: $e');
      throw Exception('Failed to add wishlist item: $e');
    }
  }

  // Update a wishlist item
  static Future<void> updateWishlistItem(
    String parentId,
    String childId,
    String itemId,
    String name,
    double price,
    String description,
  ) async {
    try {
      await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .doc(itemId)
          .update({
            'name': name,
            'price': price,
            'description': description,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
    } catch (e) {
      throw Exception('Failed to update wishlist item: $e');
    }
  }

  // Delete a wishlist item
  static Future<void> deleteWishlistItem(
    String parentId,
    String childId,
    String itemId,
  ) async {
    try {
      await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .doc(itemId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete wishlist item: $e');
    }
  }

  // Toggle completion status of a wishlist item
  static Future<void> toggleWishlistItemCompletion(
    String parentId,
    String childId,
    String itemId,
    bool isCompleted,
  ) async {
    try {
      await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .doc(itemId)
          .update({
            'isCompleted': isCompleted,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
    } catch (e) {
      throw Exception('Failed to toggle wishlist item completion: $e');
    }
  }

  // Get total value of all wishlist items
  static Future<double> getTotalWishlistValue(
    String parentId,
    String childId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .where('isCompleted', isEqualTo: false)
          .get();

      double total = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        total += (data['price'] ?? 0.0).toDouble();
      }

      return total;
    } catch (e) {
      throw Exception('Failed to get total wishlist value: $e');
    }
  }

  // Mark wishlist item as purchased
  static Future<void> markWishlistItemAsPurchased(
    String parentId,
    String childId,
    String itemId,
  ) async {
    await updateWishlistItemPurchasedStatus(
      parentId,
      childId,
      itemId,
      true,
    );
  }

  static Future<void> updateWishlistItemPurchasedStatus(
    String parentId,
    String childId,
    String itemId,
    bool isPurchased,
  ) async {
    final parentRef = _firestore.collection('Parents').doc(parentId);
    final childRef = parentRef.collection('Children').doc(childId);

    final wishlistItemRef = childRef.collection('Wishlist').doc(itemId);
    final walletRef = childRef.collection('Wallet').doc('wallet001');

    try {
      await _firestore.runTransaction((transaction) async {
        final wishlistSnapshot = await transaction.get(wishlistItemRef);

        if (!wishlistSnapshot.exists) {
          throw Exception('Wishlist item not found');
        }

        final data = wishlistSnapshot.data() as Map<String, dynamic>;
        final bool purchaseDeducted = data['purchaseDeducted'] == true;
        final double price =
            _parseToDouble(data['price'] ?? data['itemPrice'] ?? 0.0);
        final walletSnapshot = await transaction.get(walletRef);

        if (!walletSnapshot.exists) {
          throw Exception('Wallet not found for child');
        }

        if (isPurchased && !purchaseDeducted) {
          final walletData = walletSnapshot.data() as Map<String, dynamic>;
          final double currentSpendingBalance = _parseToDouble(
            walletData['spendingBalance'] ?? walletData['spendingsBalance'],
          );

          final double newSpendingBalance =
              (currentSpendingBalance - price).clamp(0.0, double.infinity);

          transaction.update(walletRef, {
            'spendingBalance': newSpendingBalance,
            'spendingsBalance': newSpendingBalance,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          transaction.update(wishlistItemRef, {
            'isPurchased': true,
            'purchaseDeducted': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(wishlistItemRef, {
            'isPurchased': isPurchased,
            'purchaseDeducted': isPurchased ? true : false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      throw Exception(
        'Failed to update wishlist item purchase status: $e',
      );
    }
  }

  static Future<void> _ensurePurchaseDeduction(
    String parentId,
    String childId,
    WishlistItem item,
  ) async {
    final wishlistItemRef = _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Wishlist')
        .doc(item.id);

    final walletRef = _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Wallet')
        .doc('wallet001');

    await _firestore.runTransaction((transaction) async {
      final wishlistSnapshot = await transaction.get(wishlistItemRef);

      if (!wishlistSnapshot.exists) {
        return;
      }

      final data = wishlistSnapshot.data() as Map<String, dynamic>;
      final bool isPurchased = data['isPurchased'] == true;
      final bool purchaseDeducted = data['purchaseDeducted'] == true;

      if (!isPurchased || purchaseDeducted) {
        return;
      }

      final double price =
          _parseToDouble(data['price'] ?? data['itemPrice'] ?? item.price);

      if (price <= 0) {
        transaction.update(wishlistItemRef, {
          'purchaseDeducted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final walletSnapshot = await transaction.get(walletRef);

      if (!walletSnapshot.exists) {
        throw Exception('Wallet not found for child');
      }

      final walletData = walletSnapshot.data() as Map<String, dynamic>;
      final double currentSpendingBalance = _parseToDouble(
        walletData['spendingBalance'] ?? walletData['spendingsBalance'],
      );

      final double newSpendingBalance =
          (currentSpendingBalance - price).clamp(0.0, double.infinity);

      transaction.update(walletRef, {
        'spendingBalance': newSpendingBalance,
        'spendingsBalance': newSpendingBalance,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(wishlistItemRef, {
        'purchaseDeducted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static void _handleAutomaticPurchaseAdjustment(
    String parentId,
    String childId,
    WishlistItem item,
  ) {
    if (!item.isPurchased || item.purchaseDeducted) {
      return;
    }

    final key = '$parentId::$childId::${item.id}';

    if (_processingPurchaseAdjustments.contains(key)) {
      return;
    }

    _processingPurchaseAdjustments.add(key);

    Future<void>(() async {
      try {
        await _ensurePurchaseDeduction(parentId, childId, item);
      } catch (e) {
        print(
          '❌ WishlistService: Failed to ensure purchase deduction for ${item.id}: $e',
        );
      } finally {
        _processingPurchaseAdjustments.remove(key);
      }
    });
  }

  static double _parseToDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
