import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';

/// TaskFormScreen provides a dedicated screen for adding or editing a task.
/// Includes validation for title and description, as well as DatePicker and TimePicker
/// for setting task reminders.
class TaskFormScreen extends StatefulWidget {
  final Task? task; // Null when creating a task; populated when editing

  const TaskFormScreen({super.key, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  DateTime? _selectedReminderDateTime;
  bool _isSaving = false;

  bool get isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.task?.description ?? '');
    _selectedReminderDateTime = widget.task?.reminderDateTime;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Displays DatePicker and TimePicker sequentially to set the task reminder.
  Future<void> _pickReminderDateTime() async {
    final now = DateTime.now();
    final initialDate = _selectedReminderDateTime ?? now;

    // Pick Date
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );

    if (pickedDate == null || !mounted) return;

    // Pick Time
    final initialTime = TimeOfDay.fromDateTime(_selectedReminderDateTime ?? now);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime == null || !mounted) return;

    final combinedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // Validate that picked time is in the future
    if (combinedDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reminder date and time in the future.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _selectedReminderDateTime = combinedDateTime;
    });
  }

  /// Clears the currently selected reminder
  void _clearReminder() {
    setState(() {
      _selectedReminderDateTime = null;
    });
  }

  /// Validates inputs, saves task to SQLite and Cloud Firestore, and schedules notification if applicable.
  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please correct the errors in the form.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();

      // Create updated Task instance
      final updatedTask = Task(
        id: widget.task?.id,
        title: title,
        description: description,
        isCompleted: widget.task?.isCompleted ?? false,
        reminderDateTime: _selectedReminderDateTime,
        isSynced: false,
      );

      // Save via FirebaseService (handles local SQLite & Firestore sync)
      final savedTask = await FirebaseService.instance.saveTask(updatedTask);

      // Schedule or cancel local notification reminder
      if (_selectedReminderDateTime != null && savedTask.id != null) {
        await NotificationService.instance.scheduleNotification(
          id: savedTask.id!,
          title: 'Task Reminder: ${savedTask.title}',
          body: savedTask.description.isNotEmpty
              ? savedTask.description
              : 'You have a scheduled task reminder.',
          scheduledDate: _selectedReminderDateTime!,
        );
      } else if (savedTask.id != null) {
        await NotificationService.instance.cancelNotification(savedTask.id!);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing
              ? 'Task updated successfully!'
              : 'Task created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return true to trigger reload on TaskListScreen
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Task' : 'Add New Task',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title Field
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Task Title *',
                  hintText: 'Enter task title',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Task Description *',
                  hintText: 'Enter task details',
                  prefixIcon: const Icon(Icons.description),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task description.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Reminder Selection Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.alarm, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            'Task Reminder',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedReminderDateTime != null
                                  ? 'Scheduled: ${_formatDateTime(_selectedReminderDateTime!)}'
                                  : 'No reminder set',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedReminderDateTime != null
                                    ? Colors.black87
                                    : Colors.grey,
                                fontWeight: _selectedReminderDateTime != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (_selectedReminderDateTime != null)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: 'Clear Reminder',
                              onPressed: _clearReminder,
                            ),
                          ElevatedButton.icon(
                            onPressed: _pickReminderDateTime,
                            icon: const Icon(Icons.edit_calendar, size: 18),
                            label: Text(_selectedReminderDateTime == null
                                ? 'Set Reminder'
                                : 'Change'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Save Action Button
              ElevatedButton(
                onPressed: _isSaving ? null : _saveTask,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEditing ? 'Update Task' : 'Save Task',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats DateTime object into user-friendly String
  String _formatDateTime(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day at $hour:$minute';
  }
}
