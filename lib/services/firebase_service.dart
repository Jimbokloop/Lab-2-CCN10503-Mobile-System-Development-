import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../database_helper.dart';
import '../models/task_model.dart';

/// FirebaseService manages cloud synchronization with Cloud Firestore
/// and handles offline resilience by tracking connectivity changes.
class FirebaseService {
  static final FirebaseService instance = FirebaseService._init();
  FirebaseService._init();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSubscription;
  bool _isCloudAvailable = false;

  /// Sets whether a valid Cloud Firestore project is connected.
  /// Disables network streaming if using local fallback mode.
  void setCloudAvailable(bool available) {
    _isCloudAvailable = available;
    if (!available) {
      try {
        if (Firebase.apps.isNotEmpty) {
          FirebaseFirestore.instance.disableNetwork();
        }
      } catch (e) {
        debugPrint('Firestore disableNetwork notice: $e');
      }
    } else {
      try {
        if (Firebase.apps.isNotEmpty) {
          FirebaseFirestore.instance.enableNetwork();
        }
      } catch (e) {
        debugPrint('Firestore enableNetwork notice: $e');
      }
    }
  }

  /// Returns whether cloud sync is active
  bool get isCloudAvailable => _isCloudAvailable;

  /// Returns the Firestore collection reference for tasks if cloud sync is available.
  CollectionReference<Map<String, dynamic>>? get _tasksRef {
    try {
      if (_isCloudAvailable && Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance.collection('tasks');
      }
    } catch (e) {
      debugPrint('Firebase Firestore reference error: $e');
    }
    return null;
  }

  /// Checks if device currently has active network connection
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet);
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      return false;
    }
  }

  /// Listens to real-time Cloud Firestore updates from other devices and syncs them to local SQLite.
  void setupRealtimeListener({required Function() onRemoteDataChanged}) {
    if (!_isCloudAvailable) return;
    final ref = _tasksRef;
    if (ref == null) return;

    _firestoreSubscription?.cancel();
    _firestoreSubscription = ref.snapshots().listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          final docData = change.doc.data();
          if (docData == null) continue;

          if (change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified) {
            final remoteTask = Task.fromFirestore(docData);
            if (remoteTask.id != null) {
              final existing =
                  await DatabaseHelper.instance.getTaskById(remoteTask.id!);
              if (existing == null) {
                await DatabaseHelper.instance.restoreTask(remoteTask);
              } else {
                await DatabaseHelper.instance.updateTask(remoteTask);
              }
            }
          } else if (change.type == DocumentChangeType.removed) {
            final localId = int.tryParse(change.doc.id);
            if (localId != null) {
              await DatabaseHelper.instance.deleteTask(localId);
            }
          }
        }
        onRemoteDataChanged();
      },
      onError: (error) {
        debugPrint('Firestore real-time listener notice: $error');
      },
    );
  }

  /// Listens to network connectivity changes and automatically triggers
  /// synchronization of unsynced SQLite tasks when internet connection is restored.
  void listenToConnectivity({Function(int syncedCount)? onSynced}) {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) async {
        final online = results.any((result) =>
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.ethernet);

        if (online && _isCloudAvailable) {
          debugPrint('Network restored. Starting automatic sync...');
          final synced = await syncUnsyncedTasks();
          if (synced > 0 && onSynced != null) {
            onSynced(synced);
          }
        }
      },
      onError: (error) {
        debugPrint('Connectivity listener error: $error');
      },
    );
  }

  /// Pulls all tasks from Cloud Firestore into local SQLite database.
  /// Returns the number of pulled tasks.
  Future<int> pullTasksFromCloud() async {
    if (!_isCloudAvailable) return 0;
    final online = await isOnline();
    if (!online) return 0;
    final ref = _tasksRef;
    if (ref == null) return 0;

    int count = 0;
    try {
      final snapshot = await ref.get();
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        final remoteTask = Task.fromFirestore(docData);
        if (remoteTask.id != null) {
          final existing =
              await DatabaseHelper.instance.getTaskById(remoteTask.id!);
          if (existing == null) {
            await DatabaseHelper.instance.restoreTask(remoteTask);
            count++;
          } else {
            await DatabaseHelper.instance.updateTask(remoteTask);
            count++;
          }
        }
      }
      debugPrint('Pulled $count task(s) from Cloud Firestore.');
    } catch (e) {
      debugPrint('Error pulling tasks from Cloud Firestore: $e');
    }
    return count;
  }

  /// Pushes tasks from SQLite to Cloud Firestore and pulls remote Firestore tasks into SQLite.
  /// Returns the total number of successfully synced tasks.
  Future<int> syncUnsyncedTasks({bool forceAll = false}) async {
    if (!_isCloudAvailable) {
      debugPrint('Cloud sync is disabled. Check google-services.json initialization.');
      return 0;
    }

    final online = await isOnline();
    if (!online) {
      debugPrint('Device is offline. Skipping cloud sync.');
      return 0;
    }

    final ref = _tasksRef;
    if (ref == null) {
      debugPrint('Firebase reference unavailable.');
      return 0;
    }

    int syncedCount = 0;
    try {
      // First pull existing documents from Firestore into local SQLite
      final pulledCount = await pullTasksFromCloud();
      syncedCount += pulledCount;

      List<Task> tasksToSync = await DatabaseHelper.instance.getUnsyncedTasks();

      // If all local tasks were already flagged as synced but forceAll is true, sync all tasks
      if (tasksToSync.isEmpty && forceAll) {
        debugPrint('Pushing all SQLite tasks to Firestore...');
        tasksToSync = await DatabaseHelper.instance.getTasks();
      }

      for (final task in tasksToSync) {
        if (task.id == null) continue;
        try {
          await ref
              .doc(task.id.toString())
              .set(task.toFirestore(), SetOptions(merge: true));
          await DatabaseHelper.instance.markAsSynced(task.id!);
          syncedCount++;
          debugPrint('Successfully synced task #${task.id} (${task.title}) to Firestore.');
        } catch (e) {
          debugPrint('Failed to sync task #${task.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error during sync: $e');
    }
    return syncedCount;
  }

  /// Saves a task locally to SQLite first, then attempts to sync it to Cloud Firestore.
  /// Returns the saved Task with updated ID and isSynced status.
  Future<Task> saveTask(Task task) async {
    Task localTask = task;

    try {
      if (task.id == null) {
        // Insert new task locally
        final id = await DatabaseHelper.instance.insertTask(task);
        localTask = task.copyWith(id: id);
      } else {
        // Update existing task locally
        await DatabaseHelper.instance.updateTask(task);
      }

      // Check network status and cloud availability
      final online = await isOnline();
      final ref = _tasksRef;
      if (_isCloudAvailable && online && localTask.id != null && ref != null) {
        try {
          await ref
              .doc(localTask.id.toString())
              .set(localTask.toFirestore(), SetOptions(merge: true));
          await DatabaseHelper.instance.markAsSynced(localTask.id!);
          localTask = localTask.copyWith(isSynced: true);
          debugPrint('Task #${localTask.id} saved & synced to cloud.');
        } catch (e) {
          debugPrint('Task #${localTask.id} saved locally, cloud sync deferred: $e');
        }
      } else {
        debugPrint('Task #${localTask.id} saved locally in offline/local mode.');
      }
    } catch (e) {
      debugPrint('Error saving task: $e');
      rethrow;
    }

    return localTask;
  }

  /// Deletes a task locally from SQLite and remotely from Cloud Firestore if online.
  Future<void> deleteTask(int taskId) async {
    try {
      // Delete locally
      await DatabaseHelper.instance.deleteTask(taskId);

      // Delete from Cloud Firestore if online and cloud is available
      final online = await isOnline();
      final ref = _tasksRef;
      if (_isCloudAvailable && online && ref != null) {
        try {
          await ref.doc(taskId.toString()).delete();
          debugPrint('Deleted task #$taskId from Cloud Firestore.');
        } catch (e) {
          debugPrint('Failed to delete task #$taskId from Cloud Firestore: $e');
        }
      }
    } catch (e) {
      debugPrint('Error deleting task #$taskId: $e');
      rethrow;
    }
  }

  /// Cancels network and firestore subscriptions on cleanup
  void dispose() {
    _connectivitySubscription?.cancel();
    _firestoreSubscription?.cancel();
  }
}
