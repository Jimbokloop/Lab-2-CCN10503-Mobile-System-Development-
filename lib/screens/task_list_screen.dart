import 'package:flutter/material.dart';

import '../database_helper.dart';
import '../models/task_model.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import 'task_form_screen.dart';

/// TaskListScreen displays the list of tasks stored in local SQLite database,
/// allows completion status toggling, provides edit/delete actions, supports UNDO deletion,
/// displays real-time sync indicators, and navigates to TaskFormScreen.
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseService _firebaseService = FirebaseService.instance;

  List<Task> _tasks = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();

    // Listen to real-time Cloud Firestore updates across devices
    _firebaseService.setupRealtimeListener(
      onRemoteDataChanged: () {
        if (mounted) _loadTasks();
      },
    );

    // Listen to network connectivity restoration for auto-sync
    _firebaseService.listenToConnectivity(
      onSynced: (syncedCount) {
        if (!mounted) return;
        _loadTasks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network restored: $syncedCount task(s) synced to cloud!'),
            backgroundColor: Colors.blue,
          ),
        );
      },
    );
  }

  /// Loads all tasks from local SQLite database and updates state
  Future<void> _loadTasks() async {
    try {
      final tasks = await _dbHelper.getTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading tasks: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Manually triggers sync of unsynced SQLite tasks with Cloud Firestore
  Future<void> _triggerManualSync() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final isOnline = await _firebaseService.isOnline();
      if (!isOnline) {
        if (!mounted) return;
        setState(() {
          _isSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device is offline. Cloud sync will resume when online.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final syncedCount = await _firebaseService.syncUnsyncedTasks();
      await _loadTasks();

      if (!mounted) return;
      setState(() {
        _isSyncing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(syncedCount > 0
              ? 'Synced $syncedCount task(s) to cloud!'
              : 'All tasks are up to date!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud sync error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Toggles completion status of a task
  Future<void> _toggleTaskCompletion(Task task, bool? isCompleted) async {
    try {
      final updatedTask = task.copyWith(
        isCompleted: isCompleted ?? false,
        isSynced: false,
      );
      await _firebaseService.saveTask(updatedTask);
      await _loadTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating task status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Deletes task with UNDO SnackBar functionality
  Future<void> _deleteTask(Task task) async {
    if (task.id == null) return;

    try {
      // Cancel scheduled notification if reminder was set
      if (task.reminderDateTime != null) {
        await NotificationService.instance.cancelNotification(task.id!);
      }

      // Delete task via FirebaseService (SQLite & Firestore)
      await _firebaseService.deleteTask(task.id!);
      await _loadTasks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${task.title} deleted'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              try {
                // Restore task back to database
                await _dbHelper.restoreTask(task);
                await _firebaseService.saveTask(task);

                // Re-schedule reminder notification if applicable
                if (task.reminderDateTime != null &&
                    task.reminderDateTime!.isAfter(DateTime.now())) {
                  await NotificationService.instance.scheduleNotification(
                    id: task.id!,
                    title: 'Task Reminder: ${task.title}',
                    body: task.description,
                    scheduledDate: task.reminderDateTime!,
                  );
                }

                await _loadTasks();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to restore task: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Navigates to TaskFormScreen for creating or editing a task
  Future<void> _navigateToForm({Task? task}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TaskFormScreen(task: task),
      ),
    );

    if (result == true) {
      _loadTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _tasks.where((t) => t.isCompleted).length;
    final pendingCount = _tasks.length - completedCount;
    final unsyncedCount = _tasks.where((t) => !t.isSynced).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smart Task Manager',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Colors.amber),
            tooltip: 'Test Ring Now',
            onPressed: () {
              NotificationService.instance.showInstantNotification(
                id: 999,
                title: 'Task Reminder Test',
                body: 'This is a test notification sound & alert banner!',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Test notification sent! Check top banner & notification shade.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Badge(
                    isLabelVisible: unsyncedCount > 0,
                    label: Text('$unsyncedCount'),
                    child: const Icon(Icons.sync),
                  ),
            tooltip: 'Sync with Cloud',
            onPressed: _isSyncing ? null : _triggerManualSync,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _triggerManualSync();
                await _loadTasks();
              },
              child: _tasks.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.7,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.task_alt,
                                size: 80, color: Colors.blue.shade200),
                            const SizedBox(height: 16),
                            const Text(
                              'No tasks yet',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap the + button to add your first task.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Task Dashboard Summary Card
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildDashboardItem(
                                  '${_tasks.length}', 'Total', Colors.blue),
                              _buildDashboardItem(
                                  '$completedCount', 'Completed', Colors.green),
                              _buildDashboardItem(
                                  '$pendingCount', 'Pending', Colors.orange),
                              _buildDashboardItem(
                                  '$unsyncedCount',
                                  'Unsynced',
                                  unsyncedCount > 0
                                      ? Colors.red
                                      : Colors.grey),
                            ],
                          ),
                        ),

                        // Task List
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                color: task.isCompleted
                                    ? Colors.green.shade50
                                    : Colors.white,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  leading: Checkbox(
                                    value: task.isCompleted,
                                    activeColor: Colors.green,
                                    onChanged: (value) =>
                                        _toggleTaskCompletion(task, value),
                                  ),
                                  title: Text(
                                    task.title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      decoration: task.isCompleted
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      color: task.isCompleted
                                          ? Colors.grey
                                          : Colors.black,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        task.description.isEmpty
                                            ? 'No description'
                                            : task.description,
                                        style: TextStyle(
                                          decoration: task.isCompleted
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          color: task.isCompleted
                                              ? Colors.grey
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (task.reminderDateTime != null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.alarm,
                                              size: 14,
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _formatDateTime(
                                                  task.reminderDateTime!),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Cloud Sync status badge
                                      Icon(
                                        task.isSynced
                                            ? Icons.cloud_done
                                            : Icons.cloud_off,
                                        size: 18,
                                        color: task.isSynced
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.blue),
                                        tooltip: 'Edit Task',
                                        onPressed: () =>
                                            _navigateToForm(task: task),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red),
                                        tooltip: 'Delete Task',
                                        onPressed: () => _deleteTask(task),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
    );
  }

  Widget _buildDashboardItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}
