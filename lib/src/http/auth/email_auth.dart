import 'dart:async';
import 'dart:math';

import '../../container/quds_container.dart';
import '../../routing/router.dart';
import 'auth.dart';
import 'mailer.dart';
import 'password_hasher.dart';
import 'user_store.dart';

/// Email/password registration, login, verification, and reset on top of [Auth].
class EmailAuth {
  /// When true, [login] rejects users whose email is not verified.
  static bool requireVerifiedEmail = false;

  /// Called after register with a short-lived verification JWT.
  static void Function(AuthUser user, String token)? onVerificationToken;

  /// Called after [forgotPassword] when the email exists.
  static void Function(AuthUser user, String token)? onResetToken;

  static UserStore _store() {
    if (!QudsContainer.isRegistered<UserStore>()) {
      QudsContainer.singleton<UserStore>(MemoryUserStore());
    }
    return QudsContainer.resolve<UserStore>();
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? name,
  }) async {
    final normalized = _normalizeEmail(email);
    _assertEmail(normalized);
    _assertPassword(password);

    if (await _store().findByEmail(normalized) != null) {
      throw QudsValidationException({
        'email': ['The email has already been taken.'],
      });
    }

    final user = await _store().create(
      AuthUser(
        id: _id(),
        email: normalized,
        name: name,
        passwordHash: PasswordHasher.hash(password),
        provider: 'email',
        emailVerified: false,
      ),
    );

    final verifyToken = _purposeToken(user, 'email_verify', const Duration(hours: 24));
    onVerificationToken?.call(user, verifyToken);
    _offerMail(
      user: user,
      token: verifyToken,
      purpose: 'verify_email',
      subject: 'Verify your email',
      text: 'Use this token to verify your email: $verifyToken',
    );

    final tokens = await Auth.issueTokens(user.toTokenPayload());
    return {...tokens, 'user': _publicUser(user)};
  }

  /// Returns token pair, or `null` when credentials are wrong.
  static Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    final user = await _store().findByEmail(_normalizeEmail(email));
    if (user == null || user.passwordHash == null) return null;
    if (!PasswordHasher.verify(password, user.passwordHash!)) return null;
    if (requireVerifiedEmail && !user.emailVerified) return null;

    final tokens = await Auth.issueTokens(user.toTokenPayload());
    return {...tokens, 'user': _publicUser(user)};
  }

  static Future<bool> verifyEmail(String token) async {
    final payload = _requirePurpose(token, 'email_verify');
    if (payload == null) return false;
    final user = await _store().findById(payload['sub']?.toString() ?? '');
    if (user == null) return false;
    await _store().update(user.copyWith(emailVerified: true));
    return true;
  }

  /// Always succeeds from the caller's point of view. Fires [onResetToken]
  /// only when the email exists (does not reveal that).
  static Future<void> forgotPassword(String email) async {
    final user = await _store().findByEmail(_normalizeEmail(email));
    if (user == null) return;
    final token = _purposeToken(user, 'password_reset', const Duration(hours: 2));
    onResetToken?.call(user, token);
    _offerMail(
      user: user,
      token: token,
      purpose: 'password_reset',
      subject: 'Reset your password',
      text: 'Use this token to reset your password: $token',
    );
  }

  static Future<bool> resetPassword({
    required String token,
    required String password,
  }) async {
    _assertPassword(password);
    final payload = _requirePurpose(token, 'password_reset');
    if (payload == null) return false;
    final user = await _store().findById(payload['sub']?.toString() ?? '');
    if (user == null) return false;
    await _store().update(
      user.copyWith(passwordHash: PasswordHasher.hash(password)),
    );
    return true;
  }

  static String issueVerificationToken(AuthUser user) {
    return _purposeToken(user, 'email_verify', const Duration(hours: 24));
  }

  static void reset() {
    requireVerifiedEmail = false;
    onVerificationToken = null;
    onResetToken = null;
  }

  static Map<String, dynamic> _publicUser(AuthUser user) {
    return {
      'id': user.id,
      'email': user.email,
      'name': user.name,
      'provider': user.provider,
      'emailVerified': user.emailVerified,
    };
  }

  static String _purposeToken(
    AuthUser user,
    String purpose,
    Duration expiresIn,
  ) {
    return Auth.login(
      {
        ...user.toTokenPayload(),
        'purpose': purpose,
      },
      expiresIn: expiresIn,
    );
  }

  static Map<String, dynamic>? _requirePurpose(String token, String purpose) {
    final payload = Auth.verify(token);
    if (payload == null || payload['purpose'] != purpose) return null;
    return payload;
  }

  static void _offerMail({
    required AuthUser user,
    required String token,
    required String purpose,
    required String subject,
    required String text,
  }) {
    final send = Mailer.send;
    final to = user.email;
    if (send == null || to == null || to.isEmpty) return;
    unawaited(
      Future(() async {
        try {
          await send(
            MailMessage(
              to: to,
              subject: subject,
              text: text,
              purpose: purpose,
              user: user,
              token: token,
            ),
          );
        } catch (_) {}
      }),
    );
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static void _assertEmail(String email) {
    if (!email.contains('@') || email.length < 3) {
      throw QudsValidationException({
        'email': ['The email must be a valid email address.'],
      });
    }
  }

  static void _assertPassword(String password) {
    if (password.length < 8) {
      throw QudsValidationException({
        'password': ['The password must be at least 8 characters.'],
      });
    }
  }

  static String _id() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
