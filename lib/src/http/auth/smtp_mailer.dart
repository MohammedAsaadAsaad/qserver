import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../container/quds_env.dart';
import '../../logging/quds_log.dart';
import 'mailer.dart';

/// Minimal SMTP sender used only when `MAIL_HOST` is set and [Mailer.send]
/// is still null. Apps that already assign [Mailer.send] are left alone.
class SmtpMailer {
  static Future<void> send(MailMessage message) async {
    final host = env<String>('MAIL_HOST');
    if (host == null || host.isEmpty) {
      throw StateError('MAIL_HOST is not set');
    }
    final port = env<int>('MAIL_PORT', 465) ?? 465;
    final username = env<String>('MAIL_USERNAME') ?? '';
    final password = env<String>('MAIL_PASSWORD') ?? '';
    final from = env<String>('MAIL_FROM') ??
        (username.isNotEmpty ? username : 'no-reply@$host');
    final encryption =
        (env<String>('MAIL_ENCRYPTION', 'ssl') ?? 'ssl').toLowerCase();

    final socket = encryption == 'none' || encryption == 'off'
        ? await Socket.connect(host, port, timeout: const Duration(seconds: 15))
        : await SecureSocket.connect(
            host,
            port,
            timeout: const Duration(seconds: 15),
          );

    final client = _SmtpClient(socket);
    try {
      await client.expect(220);
      await client.command('EHLO localhost', {250});
      if (username.isNotEmpty) {
        await client.command('AUTH LOGIN', {334});
        await client.command(base64.encode(utf8.encode(username)), {334});
        await client.command(base64.encode(utf8.encode(password)), {235, 250});
      }
      await client.command('MAIL FROM:<$from>', {250});
      await client.command('RCPT TO:<${message.to}>', {250, 251});
      await client.command('DATA', {354});
      final data = StringBuffer()
        ..writeln('From: $from')
        ..writeln('To: ${message.to}')
        ..writeln('Subject: ${message.subject}')
        ..writeln('Content-Type: text/plain; charset=utf-8')
        ..writeln()
        ..writeln(message.text)
        ..writeln('.');
      await client.command(data.toString().trimRight(), {250});
      await client.command('QUIT', {221, 250});
    } finally {
      await client.close();
    }
  }

  /// Binds [Mailer.send] from env when the app has not already set a hook.
  static void configureFromEnv() {
    if (Mailer.send != null) return;
    final host = env<String>('MAIL_HOST');
    if (host == null || host.isEmpty) return;
    Mailer.send = send;
    Log.info('SMTP $host', component: 'mail');
  }
}

class _SmtpClient {
  final Socket _socket;
  final StringBuffer _buffer = StringBuffer();
  Completer<void>? _wait;

  _SmtpClient(this._socket) {
    _socket.listen(
      (chunk) {
        _buffer.write(utf8.decode(chunk));
        _wait?.complete();
        _wait = null;
      },
      onError: (_) {
        _wait?.complete();
        _wait = null;
      },
      onDone: () {
        _wait?.complete();
        _wait = null;
      },
    );
  }

  Future<int> expect(int code) async {
    final line = await _readReply();
    final got = int.tryParse(line.substring(0, 3)) ?? 0;
    if (got != code) {
      throw StateError('SMTP expected $code, got: $line');
    }
    return got;
  }

  Future<int> command(String line, Set<int> ok) async {
    _socket.write('$line\r\n');
    await _socket.flush();
    final reply = await _readReply();
    final got = int.tryParse(reply.substring(0, 3)) ?? 0;
    if (!ok.contains(got)) {
      throw StateError('SMTP command failed ($got): $reply');
    }
    return got;
  }

  Future<String> _readReply() async {
    final lines = <String>[];
    while (true) {
      final line = await _readLine();
      if (line.length < 4) continue;
      lines.add(line);
      if (line[3] == ' ') break;
    }
    return lines.last;
  }

  Future<String> _readLine() async {
    while (true) {
      final text = _buffer.toString();
      final idx = text.indexOf('\n');
      if (idx >= 0) {
        final line = text.substring(0, idx).trimRight();
        _buffer
          ..clear()
          ..write(text.substring(idx + 1));
        return line;
      }
      _wait = Completer<void>();
      await _wait!.future.timeout(const Duration(seconds: 20));
    }
  }

  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }
}
