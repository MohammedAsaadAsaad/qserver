/// Application user used by [EmailAuth] and [SocialAuth].
class AuthUser {
  final String id;
  final String? email;
  final String? name;
  final String? passwordHash;
  final String provider;
  final String? providerId;
  final bool emailVerified;
  final Map<String, dynamic> extra;

  const AuthUser({
    required this.id,
    this.email,
    this.name,
    this.passwordHash,
    this.provider = 'email',
    this.providerId,
    this.emailVerified = false,
    this.extra = const {},
  });

  AuthUser copyWith({
    String? email,
    String? name,
    String? passwordHash,
    String? provider,
    String? providerId,
    bool? emailVerified,
    Map<String, dynamic>? extra,
  }) {
    return AuthUser(
      id: id,
      email: email ?? this.email,
      name: name ?? this.name,
      passwordHash: passwordHash ?? this.passwordHash,
      provider: provider ?? this.provider,
      providerId: providerId ?? this.providerId,
      emailVerified: emailVerified ?? this.emailVerified,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toTokenPayload() {
    return {
      'sub': id,
      'id': id,
      if (email != null) 'email': email,
      if (name != null) 'name': name,
      'provider': provider,
      'emailVerified': emailVerified,
    };
  }
}

/// Persists users for email and social login.
abstract class UserStore {
  Future<AuthUser?> findById(String id);

  Future<AuthUser?> findByEmail(String email);

  Future<AuthUser?> findByProvider(String provider, String providerId);

  Future<AuthUser> create(AuthUser user);

  Future<AuthUser> update(AuthUser user);
}

/// In-process store (default). Bind a database-backed [UserStore] in production.
class MemoryUserStore implements UserStore {
  final Map<String, AuthUser> _byId = {};

  @override
  Future<AuthUser?> findById(String id) async => _byId[id];

  @override
  Future<AuthUser?> findByEmail(String email) async {
    final needle = email.toLowerCase();
    for (final user in _byId.values) {
      if (user.email?.toLowerCase() == needle) return user;
    }
    return null;
  }

  @override
  Future<AuthUser?> findByProvider(String provider, String providerId) async {
    for (final user in _byId.values) {
      if (user.provider == provider && user.providerId == providerId) {
        return user;
      }
    }
    return null;
  }

  @override
  Future<AuthUser> create(AuthUser user) async {
    _byId[user.id] = user;
    return user;
  }

  @override
  Future<AuthUser> update(AuthUser user) async {
    _byId[user.id] = user;
    return user;
  }

  void clear() => _byId.clear();

  int get length => _byId.length;
}
