import 'package:tercen_json_path/json_path.dart';
import 'package:test/test.dart';

void main() {
  final parser = JsonPathAstParser();

  group('simple paths', () {
    test('root only', () {
      final ast = parser.parse(r'$');
      expect(ast.segments, isEmpty);
    });

    test('single dot name', () {
      final ast = parser.parse(r'$.name');
      expect(ast.segments, hasLength(1));
      expect(ast.segments[0], isA<DotNameSegment>());
      expect((ast.segments[0] as DotNameSegment).name, 'name');
    });

    test('chained dot names', () {
      final ast = parser.parse(r'$.teams.name');
      expect(ast.segments, hasLength(2));
      expect((ast.segments[0] as DotNameSegment).name, 'teams');
      expect((ast.segments[1] as DotNameSegment).name, 'name');
    });

    test('dot wildcard', () {
      final ast = parser.parse(r'$.teams.*');
      expect(ast.segments, hasLength(2));
      expect(ast.segments[0], isA<DotNameSegment>());
      expect(ast.segments[1], isA<WildcardSegment>());
    });

    test('bracket wildcard', () {
      final ast = parser.parse(r'$.teams[*]');
      expect(ast.segments, hasLength(2));
      expect(ast.segments[0], isA<DotNameSegment>());
      expect(ast.segments[1], isA<WildcardSegment>());
    });

    test('teams wildcard name', () {
      final ast = parser.parse(r'$.teams[*].name');
      expect(ast.segments, hasLength(3));
      expect((ast.segments[0] as DotNameSegment).name, 'teams');
      expect(ast.segments[1], isA<WildcardSegment>());
      expect((ast.segments[2] as DotNameSegment).name, 'name');
    });
  });

  group('array access', () {
    test('array index', () {
      final ast = parser.parse(r'$.teams[0]');
      expect(ast.segments, hasLength(2));
      expect(ast.segments[1], isA<ArrayIndexSegment>());
      expect((ast.segments[1] as ArrayIndexSegment).index, 0);
    });

    test('array slice', () {
      final ast = parser.parse(r'$.teams[0:5]');
      expect(ast.segments, hasLength(2));
      final slice = ast.segments[1] as ArraySliceSegment;
      expect(slice.start, 0);
      expect(slice.end, 5);
      expect(slice.step, isNull);
    });

    test('array slice with step', () {
      final ast = parser.parse(r'$.teams[::2]');
      expect(ast.segments, hasLength(2));
      final slice = ast.segments[1] as ArraySliceSegment;
      expect(slice.start, isNull);
      expect(slice.end, isNull);
      expect(slice.step, 2);
    });
  });

  group('filters', () {
    test('simple equality filter', () {
      final ast = parser.parse(r"$.teams[?@.id == 'xxx']");
      expect(ast.segments, hasLength(2));
      final filter = ast.segments[1] as FilterSegment;
      expect(filter.fieldRefs, hasLength(1));
      expect(filter.fieldRefs[0].property, 'id');
      expect(filter.fieldRefs[0].compOperator, '==');
      expect(filter.fieldRefs[0].value, 'xxx');
    });

    test('filter with double-quoted string', () {
      final ast = parser.parse(r'$.teams[?@.name == "Test"]');
      expect(ast.segments, hasLength(2));
      final filter = ast.segments[1] as FilterSegment;
      expect(filter.fieldRefs[0].property, 'name');
      expect(filter.fieldRefs[0].value, 'Test');
    });

    test('filter with OR', () {
      final ast =
          parser.parse(r"$.teams[?@.id == 'a' || @.id == 'b']");
      expect(ast.segments, hasLength(2));
      final filter = ast.segments[1] as FilterSegment;
      expect(filter.fieldRefs, hasLength(2));
      expect(filter.operator, FilterLogicalOperator.or);
      expect(filter.fieldRefs[0].value, 'a');
      expect(filter.fieldRefs[1].value, 'b');
    });

    test('filter with AND', () {
      final ast =
          parser.parse(r"$.teams[?@.name == 'x' && @.kind == 'y']");
      expect(ast.segments, hasLength(2));
      final filter = ast.segments[1] as FilterSegment;
      expect(filter.fieldRefs, hasLength(2));
      expect(filter.operator, FilterLogicalOperator.and);
    });

    test('filter inequality', () {
      final ast = parser.parse(r"$.teams[?@.count > 5]");
      expect(ast.segments, hasLength(2));
      final filter = ast.segments[1] as FilterSegment;
      expect(filter.fieldRefs[0].property, 'count');
      expect(filter.fieldRefs[0].compOperator, '>');
      expect(filter.fieldRefs[0].value, '5');
    });

    test('existence test', () {
      final ast = parser.parse(r'$.teams[?@.name]');
      expect(ast.segments, hasLength(2));
      final filter = ast.segments[1] as FilterSegment;
      expect(filter.fieldRefs[0].property, 'name');
      expect(filter.fieldRefs[0].compOperator, 'exists');
    });
  });

  group('dereference', () {
    test('simple deref', () {
      final ast = parser.parse(r'$.workflows[*].projectId@Project');
      expect(ast.segments, hasLength(3));
      final deref = ast.segments[2] as DereferenceSegment;
      expect(deref.fieldName, 'projectId');
      expect(deref.targetKind, 'Project');
    });

    test('deref then property', () {
      final ast =
          parser.parse(r'$.workflows[*].projectId@Project.name');
      expect(ast.segments, hasLength(4));
      expect(ast.segments[2], isA<DereferenceSegment>());
      expect((ast.segments[3] as DotNameSegment).name, 'name');
    });

    test('chained deref', () {
      final ast = parser.parse(
          r'$.workflows[*].projectId@Project.owner@User.name');
      expect(ast.segments, hasLength(5));
      expect(ast.segments[2], isA<DereferenceSegment>());
      expect(ast.segments[3], isA<DereferenceSegment>());
      expect((ast.segments[4] as DotNameSegment).name, 'name');
    });
  });

  group('union/projection', () {
    test('multi-field projection', () {
      final ast = parser.parse(r"$.teams[*]['name', 'kind']");
      expect(ast.segments, hasLength(3));
      final union = ast.segments[2] as UnionSegment;
      expect(union.elements, hasLength(2));
      expect((union.elements[0] as FieldNameElement).name, 'name');
      expect((union.elements[1] as FieldNameElement).name, 'kind');
    });

    test('single quoted field', () {
      final ast = parser.parse(r"$.teams[*]['name']");
      expect(ast.segments, hasLength(3));
      // Single quoted field becomes DotNameSegment
      expect((ast.segments[2] as DotNameSegment).name, 'name');
    });

    test('index union', () {
      final ast = parser.parse(r'$.teams[0, 2]');
      expect(ast.segments, hasLength(2));
      final union = ast.segments[1] as UnionSegment;
      expect(union.elements, hasLength(2));
      expect((union.elements[0] as IndexElement).index, 0);
      expect((union.elements[1] as IndexElement).index, 2);
    });
  });

  group('recursion', () {
    test('recursive dot name', () {
      final ast = parser.parse(r'$..name');
      expect(ast.segments, hasLength(1));
      final rec = ast.segments[0] as RecursionSegment;
      expect(rec.inner, isA<DotNameSegment>());
      expect((rec.inner as DotNameSegment).name, 'name');
    });

    test('recursive wildcard', () {
      final ast = parser.parse(r'$..*');
      expect(ast.segments, hasLength(1));
      final rec = ast.segments[0] as RecursionSegment;
      expect(rec.inner, isA<WildcardSegment>());
    });
  });

  group('complex paths', () {
    test('full hierarchy with filters and deref', () {
      final ast = parser.parse(
        r"$.teams[?@.id == 'xxx'].projects[*].workflows[?@.name == 'test'].projectId@Project.name",
      );
      expect(ast.segments, hasLength(8));
      expect((ast.segments[0] as DotNameSegment).name, 'teams');
      expect(ast.segments[1], isA<FilterSegment>());
      expect((ast.segments[2] as DotNameSegment).name, 'projects');
      expect(ast.segments[3], isA<WildcardSegment>());
      expect((ast.segments[4] as DotNameSegment).name, 'workflows');
      expect(ast.segments[5], isA<FilterSegment>());
      final deref = ast.segments[6] as DereferenceSegment;
      expect(deref.fieldName, 'projectId');
      expect(deref.targetKind, 'Project');
      expect((ast.segments[7] as DotNameSegment).name, 'name');
    });

    test('nested collections', () {
      final ast = parser.parse(
        r"$.teams[?@.id == 'tid'].projects[*].schemas[0].name",
      );
      expect(ast.segments, hasLength(7));
      expect((ast.segments[0] as DotNameSegment).name, 'teams');
      expect(ast.segments[1], isA<FilterSegment>());
      expect((ast.segments[2] as DotNameSegment).name, 'projects');
      expect(ast.segments[3], isA<WildcardSegment>());
      expect((ast.segments[4] as DotNameSegment).name, 'schemas');
      expect(ast.segments[5], isA<ArrayIndexSegment>());
      expect((ast.segments[6] as DotNameSegment).name, 'name');
    });
  });

  group('error handling', () {
    test('invalid expression throws FormatException', () {
      expect(() => parser.parse('invalid'), throwsFormatException);
    });

    test('missing dollar sign throws', () {
      expect(() => parser.parse('.teams'), throwsFormatException);
    });
  });

  group('position tracking', () {
    test('segments have valid positions', () {
      final ast = parser.parse(r'$.teams[*].name');
      for (final seg in ast.segments) {
        expect(seg.position, greaterThanOrEqualTo(0));
      }
    });
  });
}
