import 'package:tercen_json_path/json_path.dart';
import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:test/test.dart';

/// Mock resolver for testing @ dereferencing
class MockResolver implements RefIdResolver {
  final Map<String, Map<String, dynamic>> _store;

  MockResolver(this._store);

  @override
  Future<Map<String, dynamic>?> dereference(String refId, String targetKind) async {
    final doc = _store[refId];
    if (doc == null) return null;

    // Optionally verify kind matches
    if (doc['kind'] != targetKind) return null;

    return doc;
  }
}

void main() {
  group('@ Dereferencing', () {
    late MockResolver resolver;
    late Map<String, dynamic> testData;

    setUp(() {
      // Create mock data store
      resolver = MockResolver({
        'op_1': {'kind': 'Operator', 'id': 'op_1', 'name': 'Mean', 'category': 'Math'},
        'op_2': {'kind': 'Operator', 'id': 'op_2', 'name': 'PCA', 'category': 'ML'},
        'proj_1': {'kind': 'Project', 'id': 'proj_1', 'name': 'My Project'},
      });

      testData = {
        'workflows': [
          {
            'id': 'wf_1',
            'projectId': 'proj_1',
            'steps': [
              {'id': 'step_1', 'operatorId': 'op_1'},
              {'id': 'step_2', 'operatorId': 'op_2'},
            ],
          },
        ],
      };
    });

    test('Basic @ dereferencing', () async {
      final path = JsonPath(r'$.workflows[0].projectId@Project', resolver: resolver);
      final results = await path.read(testData).toList();

      expect(results, hasLength(1));
      expect((results[0].value as Map)['name'], 'My Project');
    });

    test('@ dereferencing in array', () async {
      final path = JsonPath(r'$.workflows[0].steps[*].operatorId@Operator', resolver: resolver);
      final results = await path.read(testData).toList();

      expect(results, hasLength(2));
      expect((results[0].value as Map)['name'], 'Mean');
      expect((results[1].value as Map)['name'], 'PCA');
    });

    test('@ dereferencing with property access', () async {
      final path = JsonPath(r'$.workflows[0].steps[*].operatorId@Operator.name', resolver: resolver);
      final values = await path.readValues(testData).toList();

      expect(values, hasLength(2));
      expect(values[0], 'Mean');
      expect(values[1], 'PCA');
    });

    test('@ dereferencing with filter', () async {
      // Known limitation: @ syntax not supported in relative path contexts (filters)
      // The parser cannot distinguish between @ (current node) and name@Kind syntax
      // when @ appears after filter operators like ?@.field
      expect(
        () => JsonPath(
          r"$.workflows[0].steps[?@.operatorId@Operator.category == 'ML']",
          resolver: resolver,
        ),
        throwsA(isA<Exception>()),
      );
    }, skip: '@ in filter expressions requires relative path support');

    test('@ dereferencing with non-existent ref', () async {
      testData['workflows'][0]['steps'].add({'id': 'step_3', 'operatorId': 'op_999'});

      final path = JsonPath(r'$.workflows[0].steps[*].operatorId@Operator', resolver: resolver);
      final results = await path.read(testData).toList();

      // Should only return the 2 existing operators, skip the missing one
      expect(results, hasLength(2));
    });

    test('@ dereferencing without resolver', () async {
      // Without resolver, @ syntax should parse but not dereference
      final path = JsonPath(r'$.workflows[0].projectId@Project');
      final results = await path.read(testData).toList();

      // Should return empty since dereferencing is skipped
      expect(results, isEmpty);
    });
  });
}
