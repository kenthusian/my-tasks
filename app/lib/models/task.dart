const _unset = Object();

/// One to-do item. Immutable; edits create a new copy via [copyWith].
class Task {
  const Task({
    required this.id,
    required this.title,
    this.notes = '',
    this.completed = false,
    this.priority = 1,
    this.dueAt,
    this.category = '',
    required this.updatedAt,
    this.version = 0,
    this.deleted = false,
    this.repeat = 0,
    this.position,
  });

  /// Client-generated UUID. Because the id is created on the device, the
  /// server can upsert by id and a retried create can never make a duplicate.
  final String id;
  final String title;
  final String notes;
  final bool completed;

  /// 0 = low, 1 = medium, 2 = high.
  final int priority;

  /// Deadline as milliseconds since epoch, or null.
  final int? dueAt;
  final String category;

  /// Local edit time (ms). Strictly increasing per task, used to break ties.
  final int updatedAt;

  /// Last server version this device knows about (0 = never synced).
  final int version;

  /// Tombstone flag: deletes are synced like edits, then hidden from the UI.
  final bool deleted;

  /// 0 = never, 1 = daily, 2 = weekly, 3 = monthly. Completing a repeating
  /// task creates the next occurrence.
  final int repeat;

  /// Manual order set by drag-and-drop (smaller = higher up). Null on tasks
  /// from before reordering existed; see [sortKey].
  final double? position;

  /// Key used to order the list: the manual position, or (newest first) the
  /// edit time for tasks that never got one.
  double get sortKey => position ?? -updatedAt.toDouble();

  /// Fields that take part in synchronisation and merging.
  static const syncedFields = [
    'title',
    'notes',
    'completed',
    'priority',
    'dueAt',
    'category',
    'deleted',
    'repeat',
    'position',
  ];

  Task copyWith({
    String? title,
    String? notes,
    bool? completed,
    int? priority,
    Object? dueAt = _unset,
    String? category,
    int? updatedAt,
    int? version,
    bool? deleted,
    int? repeat,
    Object? position = _unset,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      completed: completed ?? this.completed,
      priority: priority ?? this.priority,
      dueAt: identical(dueAt, _unset) ? this.dueAt : dueAt as int?,
      category: category ?? this.category,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deleted: deleted ?? this.deleted,
      repeat: repeat ?? this.repeat,
      position: identical(position, _unset) ? this.position : position as double?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'completed': completed,
        'priority': priority,
        'dueAt': dueAt,
        'category': category,
        'updatedAt': updatedAt,
        'version': version,
        'deleted': deleted,
        'repeat': repeat,
        'position': position,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        notes: (j['notes'] as String?) ?? '',
        completed: (j['completed'] as bool?) ?? false,
        priority: (j['priority'] as num?)?.toInt() ?? 1,
        dueAt: (j['dueAt'] as num?)?.toInt(),
        category: (j['category'] as String?) ?? '',
        updatedAt: (j['updatedAt'] as num).toInt(),
        version: (j['version'] as num?)?.toInt() ?? 0,
        deleted: (j['deleted'] as bool?) ?? false,
        repeat: (j['repeat'] as num?)?.toInt() ?? 0,
        position: (j['position'] as num?)?.toDouble(),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'notes': notes,
        'completed': completed ? 1 : 0,
        'priority': priority,
        'due_at': dueAt,
        'category': category,
        'updated_at': updatedAt,
        'version': version,
        'deleted': deleted ? 1 : 0,
        'repeat': repeat,
        'position': position,
      };

  factory Task.fromRow(Map<String, Object?> r) => Task(
        id: r['id'] as String,
        title: r['title'] as String,
        notes: r['notes'] as String,
        completed: (r['completed'] as int) == 1,
        priority: r['priority'] as int,
        dueAt: r['due_at'] as int?,
        category: r['category'] as String,
        updatedAt: r['updated_at'] as int,
        version: r['version'] as int,
        deleted: (r['deleted'] as int) == 1,
        repeat: r['repeat'] as int,
        position: (r['position'] as num?)?.toDouble(),
      );
}
