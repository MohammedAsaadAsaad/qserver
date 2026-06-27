/// The base abstract class for all validators
abstract class QudsValidator {
  final List<QudsValidator> _chain = [];

  QudsValidator() {
    _chain.add(this); // Add itself as the first rule in the chain
  }

  /// The method to be overridden by concrete validators
  String? validateRule(String field, dynamic value);

  /// Executes the entire chain of validators
  List<String> run(String field, dynamic value) {
    final errors = <String>[];
    for (var validator in _chain) {
      final error = validator.validateRule(field, value);
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

// ==========================================
// Extensions for Fluent Chaining
// ==========================================

extension QudsValidatorExtensions on QudsValidator {
  QudsValidator min(int length) => and(MinRule(length));
  QudsValidator max(int length) => and(MaxRule(length));
  QudsValidator isString() => and(IsString());
  QudsValidator isEmail() => and(IsEmail());
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
      final fieldErrors = validator.run(field, value);

      if (fieldErrors.isNotEmpty) {
        errors[field] = fieldErrors;
      }
    });

    return errors;
  }
}
