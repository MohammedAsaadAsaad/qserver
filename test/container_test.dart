import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

class TestService {
  final String value;
  TestService(this.value);
}

class TestDto {
  final String name;
  TestDto(this.name);

  factory TestDto.fromJson(Map<String, dynamic> json) {
    return TestDto(json['name'] as String);
  }
}

void main() {
  group('QudsContainer Tests', () {
    setUp(() {
      QudsContainer.clear();
    });

    test('Register and resolve singleton', () {
      final service = TestService('singleton_instance');
      QudsContainer.singleton<TestService>(service);

      final resolved = QudsContainer.resolve<TestService>();
      expect(resolved, same(service));
      expect(resolved.value, 'singleton_instance');
    });

    test('Register and resolve factory bind', () {
      int counter = 0;
      QudsContainer.bind<TestService>(() => TestService('instance_${counter++}'));

      final resolved1 = QudsContainer.resolve<TestService>();
      final resolved2 = QudsContainer.resolve<TestService>();

      expect(resolved1, isNot(same(resolved2)));
      expect(resolved1.value, 'instance_0');
      expect(resolved2.value, 'instance_1');
    });

    test('app() global helper resolves correctly', () {
      final service = TestService('global_helper');
      QudsContainer.singleton<TestService>(service);

      expect(app<TestService>(), same(service));
    });

    test('Unregistered dependency throws exception', () {
      expect(
        () => QudsContainer.resolve<TestService>(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('QudsMapper Tests', () {
    test('Register and build dynamic json model mapping', () {
      QudsMapper.register<TestDto>((json) => TestDto.fromJson(json));

      final result = QudsMapper.build<TestDto>({'name': 'Dart Framework'});
      expect(result, isNotNull);
      expect(result!.name, 'Dart Framework');
    });

    test('Unregistered mapper type throws exception', () {
      expect(
        () => QudsMapper.build<TestService>({'value': 'test'}),
        throwsA(isA<Exception>()),
      );
    });

    test('Null JSON returns null mapping', () {
      final result = QudsMapper.build<TestDto>(null);
      expect(result, isNull);
    });
  });
}
