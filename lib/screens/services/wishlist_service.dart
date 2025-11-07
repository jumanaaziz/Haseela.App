import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/wishlist_item.dart';

class WishlistService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    try {
      await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wishlist')
          .doc(itemId)
          .update({
            'isPurchased': true,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
    } catch (e) {
      throw Exception('Failed to mark wishlist item as purchased: $e');
    }
  }
}
