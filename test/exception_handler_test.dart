import 'dart:io';

import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    ServerMonitor.enabled = false;
    ExceptionLog.logToFile = false;
    ExceptionLog.clear();
  });

  tearDown(() {
    ExceptionLog.clear();
    ServerMonitor.enabled = true;
    ExceptionLog.logToFile = true;
  });

  group('GlobalExceptionHandler', () {
    test('maps validation errors to 422', () {
      final response = GlobalExceptionHandler.toResponse(
        QudsValidationException({
          'email': ['The email field is required.'],
        }),
      );

      expect(response.statusCode, 422);
      expect(response.body, contains('The given data was invalid.'));
      expect(ExceptionLog.recent, isEmpty);
    });

    test('maps authorization errors to 403', () {
      final response = GlobalExceptionHandler.toResponse(
        QudsAuthorizationException('Forbidden'),
      );

      expect(response.statusCode, 403);
      expect(response.body, contains('Forbidden'));
    });

    test('maps unexpected errors to 500', () {
      final response = GlobalExceptionHandler.toResponse(
        FormatException('bad json'),
      );

      expect(response.statusCode, 500);
      expect(GlobalExceptionHandler.statusOf(FormatException('bad json')), 500);
    });

    test('records unexpected errors for later review', () {
      GlobalExceptionHandler.handle(
        StateError('boom'),
        stackTrace: StackTrace.current,
      );

      expect(ExceptionLog.total, 1);
      expect(ExceptionLog.recent, hasLength(1));
      expect(ExceptionLog.recent.first.errorType, 'StateError');
      expect(ExceptionLog.recent.first.message, contains('boom'));
    });

    test('does not record expected validation errors by default', () {
      GlobalExceptionHandler.handle(
        QudsValidationException({
          'title': ['required'],
        }),
      );

      expect(ExceptionLog.recent, isEmpty);
    });

    test('records expected errors when logExpected is true', () {
      GlobalExceptionHandler.handle(
        QudsAuthorizationException('nope'),
        logExpected: true,
      );

      expect(ExceptionLog.total, 1);
      expect(ExceptionLog.recent.first.errorType, 'QudsAuthorizationException');
    });
  });

  group('ExceptionLog', () {
    test('keeps only maxInMemory records', () {
      final previous = ExceptionLog.maxInMemory;
      ExceptionLog.maxInMemory = 3;
      addTearDown(() => ExceptionLog.maxInMemory = previous);

      for (var i = 0; i < 5; i++) {
        ExceptionLog.add(
          QudsExceptionRecord(
            id: 'ex_$i',
            time: DateTime.now(),
            method: 'GET',
            path: '/n/$i',
            ip: '127.0.0.1',
            errorType: 'Exception',
            message: 'n=$i',
            stackTrace: '',
          ),
        );
      }

      expect(ExceptionLog.total, 5);
      expect(ExceptionLog.recent, hasLength(3));
      expect(ExceptionLog.recent.first.path, '/n/2');
      expect(ExceptionLog.recent.last.path, '/n/4');
    });

    test('appends unexpected errors to a log file', () {
      ExceptionLog.logToFile = true;
      final file = File(
        '${Directory.systemTemp.path}/qserver_exception_test.log',
      );
      final detailDir = Directory(
        '${Directory.systemTemp.path}/qserver_exception_details',
      );
      if (file.existsSync()) file.deleteSync();
      if (detailDir.existsSync()) detailDir.deleteSync(recursive: true);
      ExceptionLog.filePath = file.path;
      ExceptionLog.detailDirectory = detailDir.path;
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
        if (detailDir.existsSync()) detailDir.deleteSync(recursive: true);
        ExceptionLog.filePath = 'storage/logs/exceptions.log';
        ExceptionLog.detailDirectory = 'storage/logs/exceptions';
        ExceptionLog.logToFile = false;
      });

      ExceptionLog.add(
        QudsExceptionRecord(
          id: 'ex_file',
          time: DateTime(2026, 8, 13, 16, 25, 3),
          method: 'POST',
          path: '/api/v1/tasks',
          ip: '127.0.0.1',
          errorType: 'FormatException',
          message: 'FormatException: bad json',
          stackTrace: '#0 main',
        ),
      );

      final contents = file.readAsStringSync();
      expect(contents, contains('POST /api/v1/tasks from 127.0.0.1'));
      expect(contents, contains('FormatException: bad json'));
      expect(contents, contains('#0 main'));

      expect(ExceptionLog.recent.single.detailFilePath, isNotNull);
      final detail = File(ExceptionLog.recent.single.detailFilePath!);
      expect(detail.existsSync(), isTrue);
      expect(detail.path, endsWith('ex_file.txt'));
      expect(detail.readAsStringSync(), contains('#0 main'));
    });
  });
}
