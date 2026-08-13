/// The base abstract class for all validators
abstract class QudsValidator {
  final List<QudsValidator> _chain = [];

  QudsValidator() {
    _chain.add(this); // Add itself as the first rule in the chain
  }

  /// The method to be overridden by concrete validators
  String? validateRule(String field, dynamic value);

  /// Optional hook with access to the full payload (used by Confirmed, etc.)
  String? validateWithData(
    String field,
    dynamic value,
    Map<String, dynamic> data,
  ) {
    return validateRule(field, value);
  }

  /// Executes the entire chain of validators
  List<String> run(
    String field,
    dynamic value, [
    Map<String, dynamic>? data,
  ]) {
    final errors = <String>[];
    final payload = data ?? const <String, dynamic>{};
    for (var validator in _chain) {
      final error = validator.validateWithData(field, value, payload);
      if (error != null) {
        errors.add(error);
      }
    }
    return errors;
  }

  /// Appends another validator to the chain
  QudsValidator and(QudsValidator other) {
    _chain.add(other);
    return this;
  }
}

// ==========================================
// Built-in Validation Rules
// ==========================================

class IsRequired extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'The $field field is required.';
    }
    return null;
  }
}

class IsString extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    // We ignore nulls here so IsRequired can handle them exclusively
    if (value != null && value is! String) {
      return 'The $field must be a string.';
    }
    return null;
  }
}

class IsEmail extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    final regex = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
    );
    if (!regex.hasMatch(value.toString())) {
      return 'The $field must be a valid email address.';
    }
    return null;
  }
}

class MinRule extends QudsValidator {
  final int min;
  MinRule(this.min);

  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    if (value is String && value.length < min) {
      return 'The $field must be at least $min characters.';
    } else if (value is num && value < min) {
      return 'The $field must be at least $min.';
    }
    return null;
  }
}

class MaxRule extends QudsValidator {
  final int max;
  MaxRule(this.max);

  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    if (value is String && value.length > max) {
      return 'The $field must not exceed $max characters.';
    } else if (value is num && value > max) {
      return 'The $field must not exceed $max.';
    }
    return null;
  }
}

class IsInt extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    if (value is int) return null;
    if (value is String && int.tryParse(value) != null) return null;
    return 'The $field must be an integer.';
  }
}

class IsBool extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    if (value is bool) return null;
    if (value is String) {
      final v = value.toLowerCase();
      if (v == 'true' || v == 'false' || v == '1' || v == '0') return null;
    }
    if (value is num && (value == 0 || value == 1)) return null;
    return 'The $field must be a boolean.';
  }
}

class IsUrl extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value.toString());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'The $field must be a valid URL.';
    }
    return null;
  }
}

/// Ensures [field] matches `[field]_confirmation` in the same payload.
class IsConfirmed extends QudsValidator {
  @override
  String? validateRule(String field, dynamic value) {
    // Without full payload we cannot confirm — ValidationEngine uses validateWithData.
    return null;
  }

  @override
  String? validateWithData(
    String field,
    dynamic value,
    Map<String, dynamic> data,
  ) {
    if (value == null) return null;
    final other = data['${field}_confirmation'];
    if (value.toString() != other?.toString()) {
      return 'The $field confirmation does not match.';
    }
    return null;
  }
}

class InRule extends QudsValidator {
  final List<dynamic> allowed;
  InRule(this.allowed);

  @override
  String? validateRule(String field, dynamic value) {
    if (value == null) return null;
    final ok = allowed.any((item) => item?.toString() == value.toString());
    if (!ok) {
      return 'The selected $field is invalid.';
    }
    return null;
  }
}

// ==========================================
// Extensions for Fluent Chaining
// ==========================================

extension QudsValidatorExtensions on QudsValidator {
  QudsValidator min(int length) => and(MinRule(length));
  QudsValidator max(int length) => and(MaxRule(length));
  QudsValidator isString() => and(IsString());
  QudsValidator isEmail() => and(IsEmail());
  QudsValidator isInt() => and(IsInt());
  QudsValidator isBool() => and(IsBool());
  QudsValidator isUrl() => and(IsUrl());
  QudsValidator confirmed() => and(IsConfirmed());
  QudsValidator inList(List<dynamic> values) => and(InRule(values));
}

// ==========================================
// The Validation Engine Runner
// ==========================================

class ValidationEngine {
  static Map<String, List<String>> validate(
    Map<String, dynamic> data,
    Map<String, QudsValidator> rules,
  ) {
    final Map<String, List<String>> errors = {};

    rules.forEach((field, validator) {
      final value = data[field];
      final fieldErrors = validator.run(field, value, data);

      if (fieldErrors.isNotEmpty) {
        errors[field] = fieldErrors;
      }
    });

    return errors;
  }
}
