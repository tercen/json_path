import 'package:tercen_json_path/json_path.dart';
import 'package:test/test.dart';

void main() {
  group('StepGraphResolver', () {
    late StepGraphResolver resolver;
    late Map<String, dynamic> testWorkflow;

    setUp(() {
      resolver = StepGraphResolver();

      // Test workflow structure:
      //
      //   s1 (TableStep - root)
      //     └─> s2 (DataStep)
      //          ├─> s3 (DataStep)
      //          │    └─> s4 (JoinStep)
      //          └─────> s4 (JoinStep) - s4 has two parents: s2 and s3
      //
      testWorkflow = {
        'kind': 'Workflow',
        'id': 'wf1',
        'steps': [
          {
            'kind': 'TableStep',
            'id': 's1',
            'name': 'Table',
            'inputs': <Map<String, dynamic>>[],
            'outputs': [
              {'kind': 'OutputPort', 'id': 's1-o-0', 'name': 'table'}
            ],
          },
          {
            'kind': 'DataStep',
            'id': 's2',
            'name': 'Data1',
            'inputs': [
              {'kind': 'InputPort', 'id': 's2-i-0', 'name': 'table'}
            ],
            'outputs': [
              {'kind': 'OutputPort', 'id': 's2-o-0', 'name': 'table'}
            ],
          },
          {
            'kind': 'DataStep',
            'id': 's3',
            'name': 'Data2',
            'inputs': [
              {'kind': 'InputPort', 'id': 's3-i-0', 'name': 'table'}
            ],
            'outputs': [
              {'kind': 'OutputPort', 'id': 's3-o-0', 'name': 'table'}
            ],
          },
          {
            'kind': 'JoinStep',
            'id': 's4',
            'name': 'Join',
            'inputs': [
              {'kind': 'InputPort', 'id': 's4-i-0', 'name': 'left'},
              {'kind': 'InputPort', 'id': 's4-i-1', 'name': 'right'}
            ],
            'outputs': <Map<String, dynamic>>[],
          },
        ],
        'links': [
          {'kind': 'Link', 'inputId': 's2-i-0', 'outputId': 's1-o-0'}, // s1 -> s2
          {'kind': 'Link', 'inputId': 's3-i-0', 'outputId': 's2-o-0'}, // s2 -> s3
          {'kind': 'Link', 'inputId': 's4-i-0', 'outputId': 's2-o-0'}, // s2 -> s4
          {'kind': 'Link', 'inputId': 's4-i-1', 'outputId': 's3-o-0'}, // s3 -> s4
        ],
      };
    });

    group('isVirtualProperty', () {
      test('returns true for supported properties', () {
        expect(resolver.isVirtualProperty('parentSteps'), isTrue);
        expect(resolver.isVirtualProperty('childSteps'), isTrue);
        expect(resolver.isVirtualProperty('ancestorSteps'), isTrue);
        expect(resolver.isVirtualProperty('descendantSteps'), isTrue);
      });

      test('returns false for unsupported properties', () {
        expect(resolver.isVirtualProperty('parent'), isFalse);
        expect(resolver.isVirtualProperty('children'), isFalse);
        expect(resolver.isVirtualProperty('name'), isFalse);
        expect(resolver.isVirtualProperty('id'), isFalse);
      });
    });

    group('parentSteps', () {
      test('returns empty list for root step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's1'].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, isEmpty);
      });

      test('returns single parent', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's2'].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, hasLength(1));
        expect((results[0] as Map)['id'], 's1');
      });

      test('returns multiple parents for join step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's4'].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s2', 's3']));
      });

      test('can access parent step properties', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's2'].parentSteps[*].name",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, hasLength(1));
        expect(results[0], 'Table');
      });
    });

    group('childSteps', () {
      test('returns empty list for leaf step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's4'].childSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, isEmpty);
      });

      test('returns single child', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's1'].childSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, hasLength(1));
        expect((results[0] as Map)['id'], 's2');
      });

      test('returns multiple children', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's2'].childSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s3', 's4']));
      });
    });

    group('ancestorSteps', () {
      test('returns empty list for root step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's1'].ancestorSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, isEmpty);
      });

      test('returns all ancestors transitively', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's4'].ancestorSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s4 has ancestors: s2, s3 (parents), and s1 (grandparent via s2 and s3)
        expect(results, hasLength(3));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s1', 's2', 's3']));
      });

      test('returns ancestors for middle step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's3'].ancestorSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s3 has ancestors: s2 (parent), s1 (grandparent)
        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s1', 's2']));
      });
    });

    group('descendantSteps', () {
      test('returns empty list for leaf step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's4'].descendantSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, isEmpty);
      });

      test('returns all descendants transitively', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's1'].descendantSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s1 has descendants: s2, s3, s4
        expect(results, hasLength(3));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s2', 's3', 's4']));
      });

      test('returns descendants for middle step', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's2'].descendantSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s2 has descendants: s3, s4
        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s3', 's4']));
      });
    });

    group('chained navigation', () {
      test('parentSteps.parentSteps gets grandparents', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's3'].parentSteps[*].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s3's parent is s2, s2's parent is s1
        expect(results, hasLength(1));
        expect((results[0] as Map)['id'], 's1');
      });

      test('childSteps.childSteps gets grandchildren', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's1'].childSteps[*].childSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s1's child is s2, s2's children are s3 and s4
        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s3', 's4']));
      });
    });

    group('filtering on virtual properties', () {
      test('filter parent steps by kind', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's2'].parentSteps[?@.kind == 'TableStep']",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, hasLength(1));
        expect((results[0] as Map)['id'], 's1');
      });

      test('filter ancestors by kind', () async {
        final path = JsonPath(
          r"$.steps[?@.id == 's4'].ancestorSteps[?@.kind == 'DataStep']",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s4's ancestors include s2 and s3 which are DataSteps
        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s2', 's3']));
      });
    });

    group('edge cases', () {
      test('virtual property on non-step node returns null', () async {
        final path = JsonPath(
          r"$.links[0].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        expect(results, isEmpty);
      });

      test('workflow with no links', () async {
        final emptyWorkflow = {
          'kind': 'Workflow',
          'id': 'wf1',
          'steps': [
            {
              'kind': 'TableStep',
              'id': 's1',
              'inputs': <Map<String, dynamic>>[],
              'outputs': [
                {'id': 's1-o-0'}
              ],
            },
          ],
          'links': <Map<String, dynamic>>[],
        };

        final path = JsonPath(
          r"$.steps[0].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(emptyWorkflow).toList();

        expect(results, isEmpty);
      });

      test('workflow with missing links key', () async {
        final workflowNoLinks = {
          'kind': 'Workflow',
          'id': 'wf1',
          'steps': [
            {
              'kind': 'TableStep',
              'id': 's1',
              'inputs': <Map<String, dynamic>>[],
              'outputs': [
                {'id': 's1-o-0'}
              ],
            },
          ],
        };

        final path = JsonPath(
          r"$.steps[0].childSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(workflowNoLinks).toList();

        expect(results, isEmpty);
      });

      test('handles duplicate links gracefully', () async {
        // Add a duplicate link
        testWorkflow['links'].add(
          {'kind': 'Link', 'inputId': 's2-i-0', 'outputId': 's1-o-0'},
        );

        final path = JsonPath(
          r"$.steps[?@.id == 's2'].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // Should still return only one parent (s1), not duplicated
        expect(results, hasLength(1));
        expect((results[0] as Map)['id'], 's1');
      });
    });

    group('multiple steps query', () {
      test('get all DataStep parents', () async {
        final path = JsonPath(
          r"$.steps[?@.kind == 'DataStep'].parentSteps[*]",
          virtualPropertyResolver: resolver,
        );
        final results = await path.readValues(testWorkflow).toList();

        // s2's parent is s1, s3's parent is s2
        expect(results, hasLength(2));
        final ids = results.map((r) => (r as Map)['id']).toSet();
        expect(ids, containsAll(['s1', 's2']));
      });
    });
  });
}
