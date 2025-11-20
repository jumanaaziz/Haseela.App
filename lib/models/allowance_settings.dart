import 'package:cloud_firestore/cloud_firestore.dart';

class AllowanceSettings {
  final double weeklyAmount;
  final String dayOfWeek; // 'Sunday', 'Monday', etc.
  final bool isEnabled;
  final DateTime? lastProcessed;

  AllowanceSettings({
    required this.weeklyAmount,
    required this.dayOfWeek,
    required this.isEnabled,
    this.lastProcessed,
  });

  factory AllowanceSettings.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw Exception('AllowanceSettings document data is null');
    }

    return AllowanceSettings(
      weeklyAmount: (data['weeklyAmount'] ?? 0.0).toDouble(),
      dayOfWeek: data['dayOfWeek'] ?? 'Sunday',
      isEnabled: data['isEnabled'] ?? false,
      lastProcessed: data['lastProcessed'] != null
          ? (data['lastProcessed'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'weeklyAmount': weeklyAmount,
      'dayOfWeek': dayOfWeek,
      'isEnabled': isEnabled,
      'lastProcessed': lastProcessed != null
          ? Timestamp.fromDate(lastProcessed!)
          : null,
    };
  }

  AllowanceSettings copyWith({
    double? weeklyAmount,
    String? dayOfWeek,
    bool? isEnabled,
    DateTime? lastProcessed,
  }) {
    return AllowanceSettings(
      weeklyAmount: weeklyAmount ?? this.weeklyAmount,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      isEnabled: isEnabled ?? this.isEnabled,
      lastProcessed: lastProcessed ?? this.lastProcessed,
    );
  }
}
