import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:image_picker/image_picker.dart';
import '/models/child.dart';
import '/models/task.dart';
import '/models/wallet.dart';

class HaseelaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final storage.FirebaseStorage _storage = storage.FirebaseStorage.instance;

  // Get child document
  Future<Child?> getChild(String parentId, String childId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .get();

      if (doc.exists) {
        return Child.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error getting child: $e');
      return null;
    }
  }

  // Get all children for a parent
  Future<List<Child>> getAllChildren(String parentId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .get();

      List<Child> children = snapshot.docs
          .map((doc) => Child.fromFirestore(doc))
          .toList();

      print('Found ${children.length} children for parent $parentId');
      for (var child in children) {
        print(
          '- Child: ${child.firstName} ${child.lastName} (ID: ${child.id})',
        );
      }

      return children;
    } catch (e) {
      print('Error getting all children: $e');
      return [];
    }
  }

  // Get tasks for a specific child
  Stream<List<Task>> getTasksForChild(String parentId, String childId) {
    print('=== FETCHING TASKS ===');
    print('Parent ID: $parentId');
    print('Child ID: $childId');
    print('Collection Path: Parents/$parentId/Children/$childId/Tasks');

    return _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Tasks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((error) {
          print('=== FIREBASE ERROR ===');
          print('Error fetching tasks: $error');
          print('Error details: ${error.toString()}');
        })
        .map((snapshot) {
          print('=== SNAPSHOT RECEIVED ===');
          print('Snapshot size: ${snapshot.docs.length}');
          print('Snapshot metadata: ${snapshot.metadata}');
          print('Snapshot from cache: ${snapshot.metadata.isFromCache}');

          if (snapshot.docs.isEmpty) {
            print('⚠️  NO DOCUMENTS FOUND in the Tasks collection');
            print('Please check:');
            print('1. Does the document Parents/$parentId exist?');
            print(
              '2. Does the document Parents/$parentId/Children/$childId exist?',
            );
            print(
              '3. Are there any documents in Parents/$parentId/Children/$childId/Tasks?',
            );
            return <Task>[];
          }

          List<Task> tasks = snapshot.docs
              .map((doc) {
                print('Processing task document: ${doc.id}');
                print('Task data: ${doc.data()}');
                try {
                  Task task = Task.fromFirestore(doc).withCategoryIcon();
                  print(
                    'Successfully created task: ${task.taskName} with status: ${task.status}',
                  );
                  return task;
                } catch (e) {
                  print('Error creating task from document ${doc.id}: $e');
                  return null;
                }
              })
              .where((task) => task != null)
              .cast<Task>()
              .toList();

          print('Final tasks list: ${tasks.length} tasks');
          return tasks;
        });
  }

  // Get wallet for a child
  Stream<Wallet?> getWalletForChild(String parentId, String childId) {
    return _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Wallet')
        .doc('wallet001') // 👈 Always fetch this exact wallet
        .snapshots()
        .map((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            return Wallet.fromFirestore(snapshot, null);
          } else {
            print(
              '⚠️ No wallet001 found for child $childId under parent $parentId',
            );
            return null;
          }
        });
  }

  // Update task status
// Update task status
Future<void> updateTaskStatus(
  String parentId,
  String childId,
  String taskId,
  String status,
) async {
  try {
    DocumentSnapshot taskDoc = await _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Tasks')
        .doc(taskId)
        .get();

    if (!taskDoc.exists) {
      throw Exception('Task not found');
    }

    final taskData = taskDoc.data() as Map<String, dynamic>;
    final previousStatus = taskData['status'] as String?;
    final allowance = (taskData['allowance'] ?? 0).toDouble();

    final statusLower = status.toLowerCase();
    Map<String, dynamic> updateData = {'status': status};

    final existingCompletedDate = taskData['completedDate'];
    final shouldMarkCompleted =
        statusLower == 'completed' || statusLower == 'done';

    if (shouldMarkCompleted && existingCompletedDate == null) {
      updateData['completedDate'] = Timestamp.now();
    }

    // Update the task status
    await _firestore
        .collection('Parents')
        .doc(parentId)
        .collection('Children')
        .doc(childId)
        .collection('Tasks')
        .doc(taskId)
        .update(updateData);

    // Only add money when task moves to 'done' status
    // AND it wasn't already 'done' before
    if (statusLower == 'done' &&
        previousStatus?.toLowerCase() != 'done' &&
        allowance > 0) {
      await updateWalletBalance(parentId, childId, allowance);
    }

    // If task is rejected after being done, deduct the money
    if (statusLower == 'rejected' &&
        previousStatus?.toLowerCase() == 'done' &&
        allowance > 0) {
      await updateWalletBalance(parentId, childId, -allowance);
    }
  } catch (e) {
    print('Error updating task status: $e');
    throw e;
  }
}

  // Update wallet balance (when task is completed)
  Future<void> updateWalletBalance(
    String parentId,
    String childId,
    double amount,
  ) async {
    try {
      final walletRef = _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Wallet')
          .doc('wallet001'); // Assuming wallet001 is the document ID

      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot walletDoc = await transaction.get(walletRef);

        if (walletDoc.exists) {
          Map<String, dynamic> data = walletDoc.data() as Map<String, dynamic>;
          double currentTotal = (data['totalBalance'] ?? 0).toDouble();
          double currentSpending = (data['spendingsBalance'] ?? 0).toDouble();

         // ✅ ONLY add to totalBalance (not spendingBalance)
        transaction.update(walletRef, {
          'totalBalance': currentTotal + amount,
          'lastUpdated': Timestamp.now(),
        });
      } else {
        throw Exception('wallet001 document not found for child $childId');
      }
    });
    } catch (e) {
      print('Error updating wallet: $e');
      throw e;
    }
  }

  // Update task status with image
  Future<void> updateTaskStatusWithImage(
    String parentId,
    String childId,
    String taskId,
    String status,
    String imagePath,
  ) async {
    try {
    final statusLower = status.toLowerCase();
    Map<String, dynamic> updateData = {
      'status': status,
      'completedImagePath': imagePath, // Always save the image path
      'image': imagePath, // Also save to the new image field
    };

    if (statusLower == 'completed') {
      final taskDoc = await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Tasks')
          .doc(taskId)
          .get();

      final existingCompletedDate = taskDoc.data()?['completedDate'];
      if (existingCompletedDate == null) {
        updateData['completedDate'] = Timestamp.now();
      }
    }

      await _firestore
          .collection('Parents')
          .doc(parentId)
          .collection('Children')
          .doc(childId)
          .collection('Tasks')
          .doc(taskId)
          .update(updateData);
    } catch (e) {
      print('Error updating task status with image: $e');
      throw e;
    }
  }

  // Upload image to Firebase Storage and return download URL
  Future<String> uploadTaskImage(
    String parentId,
    String childId,
    String taskId,
    XFile imageFile,
  ) async {
    try {
      print('🔄 Starting image upload for task: $taskId');

      // Validate file exists
      File file = File(imageFile.path);
      if (!await file.exists()) {
        throw Exception('Image file does not exist');
      }

      // Check file size (max 10MB)
      int fileSizeInBytes = await file.length();
      double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
      print('📁 File size: ${fileSizeInMB.toStringAsFixed(2)} MB');

      if (fileSizeInMB > 10) {
        throw Exception(
          'Image is too large. Please choose an image smaller than 10MB.',
        );
      }

      // Add compression for large images
      if (fileSizeInMB > 2) {
        print(
          '📦 Large image detected, compression may help with upload speed',
        );
      }

      // Create a simple filename
      String fileName =
          'task_${taskId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      String path = 'task_images/$fileName';

      print('📤 Uploading to path: $path');

      // Create reference
      storage.Reference ref = _storage.ref().child(path);

      // Upload file with metadata
      storage.SettableMetadata metadata = storage.SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'taskId': taskId,
          'parentId': parentId,
          'childId': childId,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      // Upload with timeout
      storage.UploadTask uploadTask = ref.putFile(file, metadata);
      storage.TaskSnapshot snapshot = await uploadTask.timeout(
        Duration(minutes: 5), // Increased to 5 minutes
        onTimeout: () {
          throw Exception(
            'Upload timeout. Please check your internet connection and try again.',
          );
        },
      );

      print('✅ Upload completed successfully');

      // Get download URL
      String downloadUrl = await snapshot.ref.getDownloadURL().timeout(
        Duration(minutes: 2), // Increased to 2 minutes
        onTimeout: () {
          throw Exception('Failed to get download URL. Please try again.');
        },
      );

      print('🎉 Upload successful: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Upload failed: $e');

      // Provide user-friendly error messages
      if (e.toString().contains('Permission denied')) {
        throw Exception(
          'Permission denied. Please check your account permissions.',
        );
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        throw Exception(
          'Upload timed out. Your image may be too large or your internet connection is slow. Please try with a smaller image or check your connection.',
        );
      } else if (e.toString().contains('Network') ||
          e.toString().contains('connection')) {
        throw Exception(
          'Network error. Please check your internet connection and try again.',
        );
      } else if (e.toString().contains('too large')) {
        throw Exception('Image is too large. Please choose a smaller image.');
      } else if (e.toString().contains('storage/object-not-found')) {
        throw Exception('Upload failed. Please try again.');
      } else {
        throw Exception('Upload failed: ${e.toString()}');
      }
    }
  }
}
