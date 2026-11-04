/// Next due date (ms since epoch) for a repeating task: the due date moved
/// forward by one period, repeated until it lies after [now].
int nextDueAt(int dueAt, int repeat, {int? now}) {
  final current = now ?? DateTime.now().millisecondsSinceEpoch;
  var d = DateTime.fromMillisecondsSinceEpoch(dueAt);
  DateTime step(DateTime d) => switch (repeat) {
        1 => DateTime(d.year, d.month, d.day + 1, d.hour, d.minute),
        2 => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        _ => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
      };
  var guard = 0;
  do {
    d = step(d);
  } while (d.millisecondsSinceEpoch <= current && ++guard < 5000);
  return d.millisecondsSinceEpoch;
}
