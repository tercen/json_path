import 'package:test/test.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_analyzer.dart';

void main() {
  final analyzer = VirtualHierarchyAnalyzer();

  group('VirtualHierarchyAnalyzer', () {
    test('extracts single collection with ID filter', () {
      final plan = analyzer.analyze(r"$.projects[?@.id == 'proj_456']");

      expect(plan.requirements, hasLength(1));
      expect(plan.requirements[0].collection, 'projects');
      expect(plan.requirements[0].filters, hasLength(1));
      expect(plan.requirements[0].filters[0].property, 'id');
      expect(plan.requirements[0].filters[0].operator, '==');
      expect(plan.requirements[0].filters[0].value, 'proj_456');
      expect(plan.requirements[0].depth, 0);
    });

    test('extracts hierarchical collections', () {
      final plan = analyzer.analyze(
        r"$.projects[?@.id == 'proj_456'].workflows[*]",
      );

      expect(plan.requirements, hasLength(2));
      expect(plan.requirements[0].collection, 'projects');
      expect(plan.requirements[0].parentCollection, isNull);
      expect(plan.requirements[0].depth, 0);
      expect(plan.requirements[1].collection, 'workflows');
      expect(plan.requirements[1].parentCollection, 'projects');
      expect(plan.requirements[1].depth, 1);
    });

    test('extracts property filters', () {
      final plan = analyzer.analyze(r"$.projects[?@.name == 'Test']");

      expect(plan.requirements[0].filters[0].property, 'name');
      expect(plan.requirements[0].filters[0].value, 'Test');
      expect(plan.requirements[0].hasNonIdFilters, isTrue);
    });

    test('identifies ID filter correctly', () {
      final plan = analyzer.analyze(r"$.projects[?@.id == 'proj_456']");

      expect(plan.requirements[0].idFilter, 'proj_456');
      expect(plan.requirements[0].hasNonIdFilters, isFalse);
    });

    test('handles wildcards', () {
      final plan = analyzer.analyze(r"$.projects[*].workflows[*]");

      expect(plan.requirements, hasLength(2));
      expect(plan.requirements[0].filters, isEmpty);
      expect(plan.requirements[1].filters, isEmpty);
    });

    test('handles multi-level hierarchy', () {
      final plan = analyzer.analyze(
        r"$.teams[?@.id == 'team_123'].projects[?@.id == 'proj_456'].workflows[*]",
      );

      expect(plan.requirements, hasLength(3));
      expect(plan.requirements[0].collection, 'teams');
      expect(plan.requirements[0].depth, 0);
      expect(plan.requirements[1].collection, 'projects');
      expect(plan.requirements[1].parentCollection, 'teams');
      expect(plan.requirements[1].depth, 1);
      expect(plan.requirements[2].collection, 'workflows');
      expect(plan.requirements[2].parentCollection, 'projects');
      expect(plan.requirements[2].depth, 2);
    });

    test('supports various operators', () {
      final testCases = [
        (r"$.projects[?@.count > '10']", '>'),
        (r"$.projects[?@.count < '10']", '<'),
        (r"$.projects[?@.count >= '10']", '>='),
        (r"$.projects[?@.count <= '10']", '<='),
        (r"$.projects[?@.status != 'active']", '!='),
      ];

      for (final (expression, expectedOp) in testCases) {
        final plan = analyzer.analyze(expression);
        expect(
          plan.requirements[0].filters[0].operator,
          expectedOp,
          reason: 'Failed for expression: $expression',
        );
      }
    });

    test('handles empty result for non-collection paths', () {
      final plan = analyzer.analyze(r"$.someField.anotherField");

      expect(plan.requirements, isEmpty);
      expect(plan.needsVirtualHierarchy, isFalse);
    });

    test('handles basic root queries', () {
      final plan = analyzer.analyze(r"$.workflows[*]");

      expect(plan.requirements, hasLength(1));
      expect(plan.requirements[0].collection, 'workflows');
      expect(plan.requirements[0].parentCollection, isNull);
      expect(plan.requirements[0].depth, 0);
    });

    test('supports all recognized collections', () {
      final collections = [
        'projects',
        'teams',
        'workflows',
        'schemas',
        'files',
        'folders',
        'operators',
        'tasks',
        'users',
      ];

      for (final collection in collections) {
        final plan = analyzer.analyze('\$.$collection[*]');
        expect(
          plan.requirements.any((r) => r.collection == collection),
          isTrue,
          reason: 'Collection $collection not recognized',
        );
      }
    });

    test('needsVirtualHierarchy returns correct value', () {
      final planWithRequirements = analyzer.analyze(r"$.projects[*]");
      expect(planWithRequirements.needsVirtualHierarchy, isTrue);

      final planWithoutRequirements = analyzer.analyze(r"$.someField");
      expect(planWithoutRequirements.needsVirtualHierarchy, isFalse);
    });
  });
}
