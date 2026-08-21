import 'user_store.dart';

/// Outbound mail payload. Apps set [Mailer.send]; the framework never opens SMTP.
class MailMessage {
  final String to;
  final String subject;
  final String text;
  final String purpose;
  final AuthUser? user;
  final String? token;

  const MailMessage({
    required this.to,
    required this.subject,
    required this.text,
    required this.purpose,
    this.user,
    this.token,
  });
}

/// Optional delivery hook used by [EmailAuth] when the dedicated token
/// callbacks are not enough. Existing [EmailAuth.onVerificationToken] /
/// [EmailAuth.onResetToken] handlers still run and still win for apps that
/// already send mail themselves.
class Mailer {
  /// If set, verify/reset tokens are also offered here.
  static Future<void> Function(MailMessage message)? send;

  static void reset() {
    send = null;
  }
}
