import 'dart:convert';
import 'package:tercen_json_path/json_path.dart';

/// Example: Using @ dereferencing with a mock CouchDB-like resolver
void main() async {
  // Example: Workflow data with RefIds
  final workflowData = {
    'workflows': [
      {
        'id': 'wf_1',
        'name': 'Data Analysis Pipeline',
        'projectId': 'proj_abc',
        'steps': [
          {'id': 'step_1', 'operatorId': 'op_mean', 'order': 1},
          {'id': 'step_2', 'operatorId': 'op_pca', 'order': 2},
          {'id': 'step_3', 'operatorId': 'op_plot', 'order': 3},
        ],
      },
    ],
  };

  // Create a mock resolver (in production, this would query CouchDB)
  final resolver = MockCouchDBResolver({
    'proj_abc': {
      'kind': 'Project',
      'id': 'proj_abc',
      'name': 'Cancer Research Analysis',
      'ownerId': 'user_alice',
    },
    'op_mean': {
      'kind': 'Operator',
      'id': 'op_mean',
      'name': 'Mean',
      'category': 'Math',
      'description': 'Calculate arithmetic mean',
    },
    'op_pca': {
      'kind': 'Operator',
      'id': 'op_pca',
      'name': 'Principal Component Analysis',
      'category': 'ML',
      'description': 'Dimensionality reduction',
    },
    'op_plot': {
      'kind': 'Operator',
      'id': 'op_plot',
      'name': 'Scatter Plot',
      'category': 'Visualization',
      'description': 'Create scatter plot',
    },
    'user_alice': {
      'kind': 'User',
      'id': 'user_alice',
      'name': 'Alice Johnson',
      'email': 'alice@example.com',
    },
  });

  print('=== @ Dereferencing Examples ===\n');

  // Example 1: Basic dereferencing
  print('1. Get project details:');
  final projectPath = JsonPath(
    r'$.workflows[0].projectId@Project.name',
    resolver: resolver,
  );
  final projectName = await projectPath.readValues(workflowData).single;
  print('   Project: $projectName\n');

  // Example 2: Dereference in array
  print('2. Get all operator names:');
  final operatorPath = JsonPath(
    r'$.workflows[0].steps[*].operatorId@Operator.name',
    resolver: resolver,
  );
  final operatorNames = await operatorPath.readValues(workflowData).toList();
  print('   Operators: ${operatorNames.join(', ')}\n');

  // Example 3: Get multiple properties
  print('3. Get operator details:');
  final detailsPath = JsonPath(
    r'$.workflows[0].steps[*].operatorId@Operator',
    resolver: resolver,
  );
  final operators = await detailsPath.read(workflowData).toList();
  for (final op in operators) {
    final data = op.value as Map;
    print('   - ${data['name']} (${data['category']}): ${data['description']}');
  }
  print('');

  // Example 4: Multiple different dereferences
  print('4. Get project and operators:');
  final projectMatch = await JsonPath(r'$.workflows[0].projectId@Project', resolver: resolver)
      .read(workflowData)
      .single;
  final opsMatches = await JsonPath(r'$.workflows[0].steps[*].operatorId@Operator', resolver: resolver)
      .read(workflowData)
      .toList();
  final project = projectMatch.value as Map;
  print('   Project: ${project['name']}');
  print('   Has ${opsMatches.length} operators\n');

  // Example 5: Nested property access
  print('5. Complex property chains:');
  final categoryPath = JsonPath(
    r'$.workflows[0].steps[*].operatorId@Operator.category',
    resolver: resolver,
  );
  final categories = await categoryPath.readValues(workflowData).toList();
  final uniqueCategories = categories.toSet();
  print('   Categories used: ${uniqueCategories.join(', ')}\n');

  // Example 6: Handle missing references
  print('6. Handling missing references:');
  final dataWithMissing = {
    'steps': [
      {'id': 'step_1', 'operatorId': 'op_mean'},
      {'id': 'step_2', 'operatorId': 'op_missing'}, // This doesn't exist
      {'id': 'step_3', 'operatorId': 'op_pca'},
    ],
  };
  final safePath = JsonPath(
    r'$.steps[*].operatorId@Operator.name',
    resolver: resolver,
  );
  final safeResults = await safePath.readValues(dataWithMissing).toList();
  print('   Found ${safeResults.length} operators (missing ref skipped)');
  print('   Names: ${safeResults.join(', ')}\n');

  // Example 7: Without resolver (syntax is parsed but not executed)
  print('7. Without resolver:');
  final noResolverPath = JsonPath(r'$.workflows[0].projectId@Project');
  final noResolverResults = await noResolverPath.read(workflowData).toList();
  print('   Results without resolver: ${noResolverResults.length} (empty)\n');

  print('=== Performance Stats ===');
  print('Total dereferences: ${resolver.queryCount}');
  print('Average time: ${resolver.averageTime.toStringAsFixed(2)}ms');
}

/// Mock CouchDB resolver for demonstration
class MockCouchDBResolver implements RefIdResolver {
  final Map<String, Map<String, dynamic>> _store;
  int queryCount = 0;
  int totalTimeMs = 0;

  MockCouchDBResolver(this._store);

  double get averageTime => queryCount > 0 ? totalTimeMs / queryCount : 0;

  @override
  Future<Map<String, dynamic>?> dereference(
    String refId,
    String targetKind,
  ) async {
    final start = DateTime.now();

    // Simulate network latency
    await Future.delayed(Duration(milliseconds: 10));

    queryCount++;
    totalTimeMs += DateTime.now().difference(start).inMilliseconds;

    final doc = _store[refId];

    // Verify document exists and kind matches
    if (doc == null) {
      print('   [Resolver] Document not found: $refId');
      return null;
    }

    if (doc['kind'] != targetKind) {
      print('   [Resolver] Kind mismatch: expected $targetKind, got ${doc['kind']}');
      return null;
    }

    print('   [Resolver] Resolved $refId → ${doc['name']}');
    return doc;
  }
}
