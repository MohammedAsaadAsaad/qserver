import '../../routing/router.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import '../validator.dart';
import 'auth.dart';
import 'email_auth.dart';
import 'social_auth.dart';

/// Optional HTTP endpoints for [EmailAuth] and [SocialAuth].
///
/// Not registered automatically — call [register] from your app bootstrap.
class AuthRoutes {
  static void register(QudsRouter router, {String prefix = '/auth'}) {
    final p = prefix.endsWith('/') ? prefix.substring(0, prefix.length - 1) : prefix;

    router.post('$p/register', _register);
    router.post('$p/login', _login);
    router.post('$p/refresh', _refresh);
    router.post('$p/forgot-password', _forgot);
    router.post('$p/reset-password', _reset);
    router.post('$p/verify-email', _verifyEmail);
    router.post('$p/google', (r) => _social(r, 'google', 'idToken'));
    router.post('$p/apple', (r) => _social(r, 'apple', 'identityToken'));
    router.post('$p/firebase', (r) => _social(r, 'firebase', 'idToken'));
  }

  static Future<QudsResponse> _register(QudsRequest request) async {
    request.validate({
      'email': IsRequired().isEmail(),
      'password': IsRequired().isString().min(8),
    });
    final result = await EmailAuth.register(
      email: request.input<String>('email')!,
      password: request.input<String>('password')!,
      name: request.input<String>('name'),
    );
    return QudsResponse.json(result, status: 201);
  }

  static Future<QudsResponse> _login(QudsRequest request) async {
    request.validate({
      'email': IsRequired().isEmail(),
      'password': IsRequired().isString(),
    });
    final result = await EmailAuth.login(
      email: request.input<String>('email')!,
      password: request.input<String>('password')!,
    );
    if (result == null) {
      return QudsResponse.error('Invalid email or password.', status: 401);
    }
    return QudsResponse.json(result);
  }

  static Future<QudsResponse> _refresh(QudsRequest request) async {
    request.validate({'refreshToken': IsRequired().isString()});
    final rotated = await Auth.refresh(request.input<String>('refreshToken')!);
    if (rotated == null) {
      return QudsResponse.error('Invalid refresh token.', status: 401);
    }
    return QudsResponse.json(rotated);
  }

  static Future<QudsResponse> _forgot(QudsRequest request) async {
    request.validate({'email': IsRequired().isEmail()});
    await EmailAuth.forgotPassword(request.input<String>('email')!);
    return QudsResponse.json({'ok': true});
  }

  static Future<QudsResponse> _reset(QudsRequest request) async {
    request.validate({
      'token': IsRequired().isString(),
      'password': IsRequired().isString().min(8),
    });
    final ok = await EmailAuth.resetPassword(
      token: request.input<String>('token')!,
      password: request.input<String>('password')!,
    );
    if (!ok) {
      return QudsResponse.error('Invalid or expired reset token.', status: 400);
    }
    return QudsResponse.json({'ok': true});
  }

  static Future<QudsResponse> _verifyEmail(QudsRequest request) async {
    request.validate({'token': IsRequired().isString()});
    final ok = await EmailAuth.verifyEmail(request.input<String>('token')!);
    if (!ok) {
      return QudsResponse.error('Invalid or expired verification token.', status: 400);
    }
    return QudsResponse.json({'ok': true});
  }

  static Future<QudsResponse> _social(
    QudsRequest request,
    String provider,
    String tokenField,
  ) async {
    request.validate({tokenField: IsRequired().isString()});
    try {
      final result = await SocialAuth.login(
        provider: provider,
        token: request.input<String>(tokenField)!,
      );
      return QudsResponse.json(result);
    } on StateError catch (e) {
      return QudsResponse.error(e.message, status: 401);
    }
  }
}
