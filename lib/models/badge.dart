import 'package:cloud_firestore/cloud_firestore.dart';

enum BadgeType {
  tenaciousTaskmaster, // 10 tasks completed
  financialFreedomFlyer, // 100 SAR saved
  conquerorsCrown, // First place in challenge
  highPriorityHero, // 4 high-priority tasks completed
  wishlistFulfillment, // 5 wishlist items purchased
}

// test
class Badge {
  final String id;
  final BadgeType type;
  final String name;
  final String description;
  final String imageAsset; // Asset path for badge image
  final DateTime? unlockedAt;
  final bool isUnlocked;

  Badge({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.imageAsset,
    this.unlockedAt,
    required this.isUnlocked,
  });

  factory Badge.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Badge(
      id: doc.id,
      type: BadgeType.values.firstWhere(
        (e) => e.toString().split('.').last == data['type'],
        orElse: () => BadgeType.tenaciousTaskmaster,
      ),
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      imageAsset: data['imageAsset'] ?? '',
      unlockedAt: data['unlockedAt'] != null
          ? (data['unlockedAt'] as Timestamp).toDate()
          : null,
      isUnlocked: data['isUnlocked'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.toString().split('.').last,
      'name': name,
      'description': description,
      'imageAsset': imageAsset,
      'unlockedAt': unlockedAt != null ? Timestamp.fromDate(unlockedAt!) : null,
      'isUnlocked': isUnlocked,
    };
  }

  static List<Badge> getDefaultBadges() {
    return [
      Badge(
        id: 'tenacious_taskmaster',
        type: BadgeType.tenaciousTaskmaster,
        name: 'Do 10 Tasks',
        description: 'Complete 10 tasks',
        imageAsset: 'assets/badges/tenacious_taskmaster.png',
        isUnlocked: false,
      ),
      Badge(
        id: 'financial_freedom_flyer',
        type: BadgeType.financialFreedomFlyer,
        name: 'Save 100 SAR',
        description: 'Save 100 SAR',
        imageAsset: 'assets/badges/financial_freedom_flyer.png',
        isUnlocked: false,
      ),
      Badge(
        id: 'conquerors_crown',
        type: BadgeType.conquerorsCrown,
        name: 'Win 1st in Challenge',
        description: 'Win first place in a challenge',
        imageAsset: 'assets/badges/conquerors_crown.png',
        isUnlocked: false,
      ),
      Badge(
        id: 'high_priority_hero',
        type: BadgeType.highPriorityHero,
        name: 'High-Priority Hero',
        description: 'Complete 4 high-priority tasks',
        imageAsset: 'assets/badges/high-piro.png',
        isUnlocked: false,
      ),
      Badge(
        id: 'wishlist_fulfillment',
        type: BadgeType.wishlistFulfillment,
        name: 'Wishlist Fulfillment',
        description: 'Purchase 5 items from wishlist',
        imageAsset: 'assets/badges/buy5-wishlist.png',
        isUnlocked: false,
      ),
    ];
  }
}
