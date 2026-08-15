import 'quds_request.dart';
import 'validator.dart';
import '../routing/router.dart'; // To access exceptions

/// The base class for all custom Form Requests.
abstract class QudsFormRequest {
  final QudsRequest request;

  QudsFormRequest(this.request);

  /// Determine if the user is authorized to make this request.
  /// Made async to support database lookups (e.g., checking if user owns a post).
  Future<bool> authorize() async => true;

  /// Get the validation rules that apply to the request.
  Map<String, QudsValidator> rules();

  /// Optional async/DB-backed rules. Override to enable Unique/Exists checks.
  Map<String, AsyncQudsValidator> asyncRules() => const {};

  /// Executes authorization and validation.
  /// Throws exceptions if either fails, halting controller execution instantly.
  Future<void> validate() async {
    // 1. Check Authorization
    if (!await authorize()) {
      throw QudsAuthorizationException(
        "You are not authorized to perform this action.",
      );
    }

    // 2. Run Validation Engine (sync + optional async)
    final async = asyncRules();
    if (async.isEmpty) {
      request.validate(rules());
    } else {
      await request.validateAsync(rules(), asyncRules: async);
    }
  }

  // ==========================================
  // Proxy methods for ultra-clean access
  // ==========================================

  T? input<T>(String key, {T? defaultValue}) =>
      request.input<T>(key, defaultValue: defaultValue);
  String? param(String key) => request.param(key);
  T? get<T>() => request.get<T>();
  List<T> getList<T>() => request.getList<T>();
}
