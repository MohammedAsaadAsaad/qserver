import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../../container/quds_container.dart';
import '../../container/quds_env.dart';
import 'auth.dart';
import 'user_store.dart';

/// Verified identity from a social / Firebase provider.
class SocialIdentity {
  final String provider;
  final String providerId;
  final String? email;
  final String? name;
  final bool emailVerified;
  final Map<String, dynamic> claims;

  const SocialIdentity({
    required this.provider,
    required this.providerId,
    this.email,
    this.name,
    this.emailVerified = false,
    this.claims = const {},
  });
}

typedef SocialIdentityVerifier = Future<SocialIdentity> Function(String token);

/// Google / Apple / Firebase sign-in that issues the same JWT pair as [Auth].
class SocialAuth {
  /// Replace a provider verifier in tests or to use a custom IdP.
  static final Map<String, SocialIdentityVerifier> verifiers = {
    'google': defaultGoogleVerifier,
    'apple': defaultAppleVerifier,
    'firebase': defaultFirebaseVerifier,
  };

  /// Override the HTTP client used by the default verifiers.
  static http.Client? httpClient;

  static UserStore _store() {
    if (!QudsContainer.isRegistered<UserStore>()) {
      QudsContainer.singleton<UserStore>(MemoryUserStore());
    }
    return QudsContainer.resolve<UserStore>();
  }

  static http.Client get _client => httpClient ?? http.Client();

  static Future<Map<String, dynamic>> login({
    required String provider,
    required String token,
  }) async {
    final verifier = verifiers[provider];
    if (verifier == null) {
      throw StateError('Unknown social provider: $provider');
    }
    final identity = await verifier(token);
    final user = await _findOrCreate(identity);
    final tokens = await Auth.issueTokens(user.toTokenPayload());
    return {
      ...tokens,
      'user': {
        'id': user.id,
        'email': user.email,
        'name': user.name,
        'provider': user.provider,
        'emailVerified': user.emailVerified,
      },
    };
  }

  static Future<Map<String, dynamic>> loginWithGoogle(String idToken) {
    return login(provider: 'google', token: idToken);
  }

  static Future<Map<String, dynamic>> loginWithApple(String identityToken) {
    return login(provider: 'apple', token: identityToken);
  }

  static Future<Map<String, dynamic>> loginWithFirebase(String idToken) {
    return login(provider: 'firebase', token: idToken);
  }

  static Future<AuthUser> _findOrCreate(SocialIdentity identity) async {
    final store = _store();
    var user = await store.findByProvider(identity.provider, identity.providerId);
    if (user != null) return user;

    if (identity.email != null && identity.email!.isNotEmpty) {
      user = await store.findByEmail(identity.email!);
      if (user != null) {
        return store.update(
          user.copyWith(
            provider: identity.provider,
            providerId: identity.providerId,
            emailVerified: user.emailVerified || identity.emailVerified,
            name: user.name ?? identity.name,
          ),
        );
      }
    }

    return store.create(
      AuthUser(
        id: identity.providerId,
        email: identity.email?.toLowerCase(),
        name: identity.name,
        provider: identity.provider,
        providerId: identity.providerId,
        emailVerified: identity.emailVerified,
      ),
    );
  }

  static Future<SocialIdentity> defaultGoogleVerifier(String idToken) async {
    final uri = Uri.parse(
      'https://oauth2.googleapis.com/tokeninfo?id_token=${Uri.encodeQueryComponent(idToken)}',
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Google token verification failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final expectedAud = env<String>('GOOGLE_CLIENT_ID');
    if (expectedAud != null &&
        expectedAud.isNotEmpty &&
        data['aud']?.toString() != expectedAud) {
      throw StateError('Google token audience mismatch');
    }
    final emailVerified = data['email_verified']?.toString() == 'true' ||
        data['email_verified'] == true;
    return SocialIdentity(
      provider: 'google',
      providerId: data['sub']?.toString() ?? '',
      email: data['email']?.toString(),
      name: data['name']?.toString(),
      emailVerified: emailVerified,
      claims: data,
    );
  }

  static Future<SocialIdentity> defaultAppleVerifier(String identityToken) async {
    final decoded = JWT.decode(identityToken);
    final kid = decoded.header?['kid']?.toString();
    if (kid == null || kid.isEmpty) {
      throw StateError('Apple token is missing kid');
    }

    final keysResponse = await _client.get(
      Uri.parse('https://appleid.apple.com/auth/keys'),
    );
    if (keysResponse.statusCode != 200) {
      throw StateError('Failed to fetch Apple JWKS (${keysResponse.statusCode})');
    }
    final body = jsonDecode(keysResponse.body) as Map<String, dynamic>;
    final keys = (body['keys'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final jwk = keys.cast<Map<String, dynamic>?>().firstWhere(
          (k) => k?['kid'] == kid,
          orElse: () => null,
        );
    if (jwk == null) {
      throw StateError('Apple JWKS has no key for kid $kid');
    }

    final jwt = JWT.verify(
      identityToken,
      JWTKey.fromJWK(jwk),
      issuer: 'https://appleid.apple.com',
      checkHeaderType: false,
    );
    final payload = jwt.payload as Map<String, dynamic>;
    final expectedAud = env<String>('APPLE_CLIENT_ID');
    if (expectedAud != null &&
        expectedAud.isNotEmpty &&
        payload['aud']?.toString() != expectedAud) {
      throw StateError('Apple token audience mismatch');
    }
    return SocialIdentity(
      provider: 'apple',
      providerId: payload['sub']?.toString() ?? '',
      email: payload['email']?.toString(),
      name: null,
      emailVerified: payload['email_verified'] == true ||
          payload['email_verified']?.toString() == 'true',
      claims: payload,
    );
  }

  static Future<SocialIdentity> defaultFirebaseVerifier(String idToken) async {
    final apiKey = env<String>('FIREBASE_API_KEY');
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('FIREBASE_API_KEY is required to verify Firebase tokens');
    }
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey',
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Firebase token verification failed (${response.statusCode})',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final users = data['users'] as List?;
    if (users == null || users.isEmpty) {
      throw StateError('Firebase token did not resolve a user');
    }
    final user = users.first as Map<String, dynamic>;
    return SocialIdentity(
      provider: 'firebase',
      providerId: user['localId']?.toString() ?? '',
      email: user['email']?.toString(),
      name: user['displayName']?.toString(),
      emailVerified: user['emailVerified'] == true,
      claims: user,
    );
  }

  static void reset() {
    httpClient = null;
    verifiers
      ..clear()
      ..addAll({
        'google': defaultGoogleVerifier,
        'apple': defaultAppleVerifier,
        'firebase': defaultFirebaseVerifier,
      });
  }
}
