import 'package:tercen_json_path/json_path.dart';
import 'package:test/test.dart';

void main() {
  group('Projection', () {
    test('simple projection selects only specified fields', () async {
      final jp = JsonPath(r'$[*]{a, b}');
      final values = await jp
          .readValues([
            {'a': 1, 'b': 2, 'c': 3}
          ])
          .toList();
      expect(values, [
        {'a': 1, 'b': 2}
      ]);
    });

    test('deep path projection preserves nesting', () async {
      final jp = JsonPath(r'$[*]{x.y, name}');
      final values = await jp
          .readValues([
            {
              'x': {'y': 1},
              'name': 'a'
            }
          ])
          .toList();
      expect(values, [
        {
          'x': {'y': 1},
          'name': 'a'
        }
      ]);
    });

    test('missing fields omitted from result', () async {
      final jp = JsonPath(r'$[*]{a, b, missing}');
      final values = await jp
          .readValues([
            {'a': 1, 'b': 2, 'c': 3}
          ])
          .toList();
      expect(values, [
        {'a': 1, 'b': 2}
      ]);
    });

    test('multiple deep paths with shared prefix merge', () async {
      final jp = JsonPath(r'$[*]{acl.owner, acl.permissions}');
      final values = await jp
          .readValues([
            {
              'acl': {'owner': 'admin', 'permissions': ['read', 'write']},
              'name': 'doc1'
            }
          ])
          .toList();
      expect(values, [
        {
          'acl': {
            'owner': 'admin',
            'permissions': ['read', 'write']
          }
        }
      ]);
    });

    test('all fields missing yields no result', () async {
      final jp = JsonPath(r'$[*]{x, y, z}');
      final values = await jp
          .readValues([
            {'a': 1, 'b': 2}
          ])
          .toList();
      expect(values, isEmpty);
    });

    test('single field projection', () async {
      final jp = JsonPath(r'$[*]{name}');
      final values = await jp
          .readValues([
            {'name': 'Alice', 'age': 30},
            {'name': 'Bob', 'age': 25},
          ])
          .toList();
      expect(values, [
        {'name': 'Alice'},
        {'name': 'Bob'},
      ]);
    });

    test('projection after filter', () async {
      final jp = JsonPath(r"$[?@.active == true]{name, id}");
      final values = await jp
          .readValues([
            {'name': 'Alice', 'id': '1', 'active': true},
            {'name': 'Bob', 'id': '2', 'active': false},
            {'name': 'Charlie', 'id': '3', 'active': true},
          ])
          .toList();
      expect(values, [
        {'name': 'Alice', 'id': '1'},
        {'name': 'Charlie', 'id': '3'},
      ]);
    });

    test('projection on nested collection', () async {
      final jp = JsonPath(r'$.teams[*]{name, kind}');
      final data = {
        'teams': [
          {'name': 'Team A', 'kind': 'Team', 'id': '1', 'extra': true},
          {'name': 'Team B', 'kind': 'Team', 'id': '2', 'extra': false},
        ]
      };
      final values = await jp.readValues(data).toList();
      expect(values, [
        {'name': 'Team A', 'kind': 'Team'},
        {'name': 'Team B', 'kind': 'Team'},
      ]);
    });

    test('projection with multiple items', () async {
      final jp = JsonPath(r'$[*]{a, b}');
      final values = await jp
          .readValues([
            {'a': 1, 'b': 2, 'c': 3},
            {'a': 4, 'b': 5, 'c': 6},
            {'a': 7, 'b': 8, 'c': 9},
          ])
          .toList();
      expect(values, [
        {'a': 1, 'b': 2},
        {'a': 4, 'b': 5},
        {'a': 7, 'b': 8},
      ]);
    });
  });
}
