import '../../routing/router.dart';

/// Named authorization checks. Nothing is registered until [define] is called.
typedef GateCheck = bool Function(dynamic user, Object? argument);

class Gate {
  static final Map<String, GateCheck> _abilities = {};

  static void define(String ability, GateCheck check) {
    _abilities[ability] = check;
  }

  static bool allows(String ability, dynamic user, [Object? argument]) {
    final check = _abilities[ability];
    if (check == null) return false;
    return check(user, argument);
  }

  static bool denies(String ability, dynamic user, [Object? argument]) =>
      !allows(ability, user, argument);

  static void authorize(String ability, dynamic user, [Object? argument]) {
    if (denies(ability, user, argument)) {
      throw QudsAuthorizationException('This action is unauthorized.');
    }
  }

  static void clear() => _abilities.clear();
}
