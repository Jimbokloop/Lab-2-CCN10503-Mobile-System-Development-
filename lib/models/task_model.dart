/// Task data model representing a single task item.
/// Supports conversion to/from SQLite Maps and Firebase Firestore JSON.
class Task {
  final int? id; // Primary key for local SQLite storage (nullable for new tasks)
  final String title; // Task title
  final String description; // Detailed task description
  final bool isCompleted; // Task completion toggle status
  final DateTime? reminderDateTime; // Scheduled date/time for local notification reminder
  final bool isSynced; // Offline & cloud synchronization status flag

  const Task({
    this.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    this.reminderDateTime,
    this.isSynced = false,
  });

  /// Factory constructor to convert SQLite Map to Task object
  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      isCompleted: (map['isCompleted'] as int? ?? 0) == 1,
      reminderDateTime: map['reminderDateTime'] != null
          ? DateTime.tryParse(map['reminderDateTime'] as String)
          : null,
      isSynced: (map['isSynced'] as int? ?? 0) == 1,
    );
  }

  /// Converts Task object into SQLite Map representation
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted ? 1 : 0,
      'reminderDateTime': reminderDateTime?.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
    };
  }

  /// Factory constructor to convert Firebase Firestore JSON to Task object
  factory Task.fromFirestore(Map<String, dynamic> firestoreData, {int? localId}) {
    return Task(
      id: localId ?? (firestoreData['id'] as int?),
      title: firestoreData['title'] as String? ?? '',
      description: firestoreData['description'] as String? ?? '',
      isCompleted: firestoreData['isCompleted'] as bool? ?? false,
      reminderDateTime: firestoreData['reminderDateTime'] != null
          ? DateTime.tryParse(firestoreData['reminderDateTime'] as String)
          : null,
      isSynced: true, // Data fetched from Firestore is synced by definition
    );
  }

  /// Converts Task object into Firebase Firestore JSON payload
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'reminderDateTime': reminderDateTime?.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Creates a copy of the Task with updated fields
  Task copyWith({
    int? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? reminderDateTime,
    bool? isSynced,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      reminderDateTime: reminderDateTime ?? this.reminderDateTime,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          isCompleted == other.isCompleted &&
          reminderDateTime == other.reminderDateTime &&
          isSynced == other.isSynced;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      description.hashCode ^
      isCompleted.hashCode ^
      reminderDateTime.hashCode ^
      isSynced.hashCode;

  @override
  String toString() {
    return 'Task{id: $id, title: $title, description: $description, isCompleted: $isCompleted, reminderDateTime: $reminderDateTime, isSynced: $isSynced}';
  }
}
