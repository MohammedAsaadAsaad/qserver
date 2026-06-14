import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

void main() {
  group('QudsValidator Rules Tests', () {
    test('IsRequired validation', () {
      final validator = IsRequired();
      expect(validator.validateRule('name', 'John'), isNull);
      expect(validator.validateRule('name', null), isNotNull);
      expect(validator.validateRule('name', ''), isNotNull);
      expect(validator.validateRule('name', '   '), isNotNull);
    });

    test('IsString validation', () {
      final validator = IsString();
      expect(validator.validateRule('name', 'Dart'), isNull);
      expect(validator.validateRule('name', null), isNull); // Ignores null
      expect(validator.validateRule('name', 123), isNotNull);
    });

    test('IsEmail validation', () {
      final validator = IsEmail();
      expect(validator.validateRule('email', 'test@example.com'), isNull);
      expect(validator.validateRule('email', null), isNull); // Ignores null
      expect(validator.validateRule('email', 'invalid-email'), isNotNull);
      expect(validator.validateRule('email', 'invalid@'), isNotNull);
    });

    test('MinRule validation for string and number', () {
      final validator = MinRule(3);
      // String length
      expect(validator.validateRule('field', 'abc'), isNull);
      expect(validator.validateRule('field', 'ab'), isNotNull);
      
      // Numbers
      expect(validator.validateRule('field', 3), isNull);
      expect(validator.validateRule('field', 2), isNotNull);
    });

    test('MaxRule validation for string and number', () {
      final validator = MaxRule(5);
      // String length
      expect(validator.validateRule('field', 'abcde'), isNull);
      expect(validator.validateRule('field', 'abcdef'), isNotNull);
      
      // Numbers
      expect(validator.validateRule('field', 5), isNull);
      expect(validator.validateRule('field', 6), isNotNull);
    });

    test('Fluent chaining validator extensions', () {
      final rule = IsRequired().isString().min(3).max(10);
      
      expect(rule.run('field', 'hello'), isEmpty);
      expect(rule.run('field', 'he'), isNotEmpty);
      expect(rule.run('field', 'hello world too long'), isNotEmpty);
      expect(rule.run('field', 123), isNotEmpty);
      expect(rule.run('field', null), isNotEmpty);
    });
  });

  group('ValidationEngine Tests', () {
    test('Validate valid payload data', () {
      final rules = {
        'title': IsRequired().isString().min(3),
        'email': IsEmail(),
      };
      final data = {
        'title': 'Task Title',
        'email': 'user@example.com',
      };

      final errors = ValidationEngine.validate(data, rules);
      expect(errors, isEmpty);
    });

    test('Validate invalid payload returns errors map', () {
      final rules = {
        'title': IsRequired().isString().min(5),
        'email': IsEmail(),
      };
      final data = {
        'title': 'Abc',
        'email': 'bad-email',
      };

      final errors = ValidationEngine.validate(data, rules);
      expect(errors, isNotEmpty);
      expect(errors.containsKey('title'), isTrue);
      expect(errors.containsKey('email'), isTrue);
    });
  });
}
