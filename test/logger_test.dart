import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

class _NamedJob extends Job {
  @override
  String get label => 'Named work';

  @override
  Future<void> handle() async {}
}

void main() {
  tearDown(() {
    Log.reset();
    QudsContainer.clear();
    QudsEnv.set('QUDS_MONITOR', null);
    ServerMonitor.enabled = true;
    ServerMonitor.endLive();
  });

  test('formats a structured line without color', () {
    final line = Log.format(
      LogLevel.info,
      'Listening on http://127.0.0.1:8000',
      component: 'http',
      time: DateTime(2026, 8, 21, 12, 3, 15, 42),
      colored: false,
    );
    expect(line, '12:03:15.042  INFO   http      Listening on http://127.0.0.1:8000');
  });

  test('boot writes through the writer with the boot component', () {
    final lines = <String>[];
    Log.color = false;
    Log.writer = lines.add;
    Log.boot('Loading environment');
    expect(lines, hasLength(1));
    expect(lines.single, contains('INFO '));
    expect(lines.single, contains('boot'));
    expect(lines.single, contains('Loading environment'));
  });

  test('spinner logs success and failure without animating when writer is set', () async {
    final lines = <String>[];
    Log.color = false;
    Log.writer = lines.add;
    LogSpinner.enabled = false;

    final ok = Log.spinner('ExportUsers', component: 'queue');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ok.succeed();
    expect(lines.last, contains('ExportUsers'));
    expect(lines.last, contains('queue'));
    expect(lines.last, contains('+'));

    lines.clear();
    await expectLater(
      Log.withSpinner('Boom', () async => throw StateError('nope')),
      throwsA(isA<StateError>()),
    );
    expect(lines.last, contains('Boom'));
    expect(lines.last, contains('x'));
    expect(lines.last, contains('nope'));
  });

  test('queue worker reports job success through the spinner', () async {
    final lines = <String>[];
    Log.color = false;
    Log.writer = lines.add;
    LogSpinner.enabled = false;
    QudsContainer.singleton<QueueDriver>(MemoryQueueDriver());

    final worker = QueueWorker();
    await Queue.push(_NamedJob());
    worker.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await worker.stop(timeout: const Duration(seconds: 2));

    expect(lines.any((l) => l.contains('Named work') && l.contains('+')), isTrue);
  });

  test('monitor is on by default and off when QUDS_MONITOR=false', () {
    QudsEnv.set('QUDS_MONITOR', null);
    expect(ServerMonitor.monitorEnabled, isTrue);
    QudsEnv.set('QUDS_MONITOR', 'false');
    expect(ServerMonitor.monitorEnabled, isFalse);
    QudsEnv.set('QUDS_MONITOR', 'true');
    expect(ServerMonitor.monitorEnabled, isTrue);
    QudsEnv.set('QUDS_MONITOR', null);
  });

  test('monitor does not take the terminal when disabled', () {
    ServerMonitor.enabled = false;
    ServerMonitor.goLive();
    expect(ServerMonitor.isDrawing, isFalse);
    expect(ServerMonitor.capture('x'), isFalse);
    ServerMonitor.endLive();
    expect(ServerMonitor.isLive, isFalse);
  });
}
