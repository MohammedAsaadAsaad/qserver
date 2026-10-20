/// One Server-Sent Event. Used with [QudsResponse.sse] (opt-in).
class SseEvent {
  final String data;
  final String? id;
  final String? event;
  final Duration? retry;

  const SseEvent({
    required this.data,
    this.id,
    this.event,
    this.retry,
  });

  String encode() {
    final buf = StringBuffer();
    if (id != null) buf.writeln('id: $id');
    if (event != null) buf.writeln('event: $event');
    if (retry != null) buf.writeln('retry: ${retry!.inMilliseconds}');
    for (final line in data.split('\n')) {
      buf.writeln('data: $line');
    }
    buf.writeln();
    return buf.toString();
  }
}
