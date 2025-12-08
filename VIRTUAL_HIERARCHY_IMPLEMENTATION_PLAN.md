# Virtual Hierarchy Implementation Plan for tercen_json_path

## Overview
Extend the `tercen_json_path` library to support virtual hierarchy resolution, enabling lazy fetching of collections during JSONPath evaluation. This allows hierarchical queries like `$.projects[?@.id == 'proj_456'].workflows[*]` to work on empty/partial root objects by fetching data on-demand with filter look-ahead optimization.

---

## Architecture Overview

### Current State
- **Async-first design**: `Stream<Node>` with `async*` generators
- **Dereferencing support**: `RefIdResolver` for `@` syntax
- **Selector pipeline**: Each selector transforms `NodeStream` asynchronously
- **Synchronous node access**: `Node.child(key)` and `Node.element(index)` are sync

### Target State
- **Async node access**: `Future<Node?> child(key)` and `Future<Node?> element(index)`
- **Virtual collections**: Missing collections fetched lazily via resolver
- **Filter look-ahead**: Parse JSONPath once, extract all filters, prefetch optimally
- **Caching layer**: Prefetched results cached to avoid redundant queries

### Key Innovation
**Two-phase execution:**
1. **Parse & Analyze**: Extract hierarchy requirements and filters from JSONPath
2. **Prefetch & Evaluate**: Fetch all required data with filters, then evaluate

---

## Phase 1: Async Node API (1-2 days)

### Goal
Make `Node.child()` and `Node.element()` async without breaking existing functionality.

### Tasks

#### 1.1 Update Node class signature
**File**: `packages/tercen_json_path/lib/src/node.dart`

```dart
class Node<T extends Object?> {
  // Change return type from Node? to Future<Node?>
  Future<Node?> child(String key) async {
    final v = value;
    if (v is Map && v.containsKey(key)) {
      return _child(v, key);
    }
    return null;
  }

  Future<Node?> element(int offset) async {
    final v = value;
    if (v is List) {
      final index = offset < 0 ? v.length + offset : offset;
      if (index >= 0 && index < v.length) return _element(v, index);
    }
    return null;
  }

  // children already returns Stream<Node>, no change needed
}
```

#### 1.2 Update child_selector.dart
**File**: `packages/tercen_json_path/lib/src/grammar/child_selector.dart`

```dart
Selector childSelector(String key) {
  if (key.runes.any(
    (r) => r < 0 || r > 0x10FFFF || (r >= 0xD800 && r <= 0xDFFF),
  )) {
    throw const FormatException('Invalid UTF code units in childSelector.');
  }
  return (NodeStream nodes) {
    return MultiNodeStream((() async* {
      await for (final node in nodes) {
        final child = await node.child(key); // Add await
        if (child != null) {
          yield child;
        }
      }
    })());
  };
}
```

#### 1.3 Update array_index_selector.dart
**File**: `packages/tercen_json_path/lib/src/grammar/array_index_selector.dart`

```dart
Selector arrayIndexSelector(int offset) => (NodeStream nodes) {
  return MultiNodeStream((() async* {
    await for (final node in nodes) {
      final element = await node.element(offset); // Add await
      if (element != null) {
        yield element;
      }
    }
  })());
};
```

#### 1.4 Testing
- Run existing test suite to ensure no regressions
- All tests should pass with async API
- Add specific async node access tests

### Deliverables
- ✅ `Node.child()` and `Node.element()` are async
- ✅ All selectors updated to await node access
- ✅ All existing tests pass
- ✅ No functional changes yet, just API migration

### Files Modified
- `lib/src/node.dart`
- `lib/src/grammar/child_selector.dart`
- `lib/src/grammar/array_index_selector.dart`

---

## Phase 2: Hierarchy Plan & Analysis (2-3 days)

### Goal
Create data structures and parser to extract hierarchy requirements and filters from JSONPath expressions.

### Tasks

#### 2.1 Create hierarchy plan models
**File**: `packages/tercen_json_path/lib/src/virtual_hierarchy_plan.dart` (new)

```dart
/// Represents the hierarchy fetching requirements for a JSONPath query
class VirtualHierarchyPlan {
  final List<CollectionRequirement> requirements;

  VirtualHierarchyPlan(this.requirements);

  /// Check if this plan requires virtual hierarchy support
  bool get needsVirtualHierarchy => requirements.isNotEmpty;

  @override
  String toString() => 'VirtualHierarchyPlan(${requirements.length} requirements)';
}

/// Represents one collection that needs to be fetched
class CollectionRequirement {
  final String collection;           // 'projects', 'workflows', 'teams'
  final String? parentCollection;    // Parent collection in hierarchy
  final List<FilterExpression> filters; // Filters from [?@.property == value]
  final int depth;                   // Depth in hierarchy (0 = root)

  CollectionRequirement({
    required this.collection,
    this.parentCollection,
    this.filters = const [],
    required this.depth,
  });

  /// Check if this requirement has filters beyond just ID
  bool get hasNonIdFilters =>
      filters.any((f) => f.property != 'id');

  /// Get ID filter value if it exists
  String? get idFilter =>
      filters
          .firstWhere(
            (f) => f.property == 'id' && f.operator == '==',
            orElse: () => FilterExpression(property: '', operator: '', value: null),
          )
          .value as String?;

  @override
  String toString() =>
      'CollectionRequirement($collection, parent: $parentCollection, filters: $filters)';
}

/// Represents a filter extracted from JSONPath
class FilterExpression {
  final String property;    // Property name: 'id', 'name', 'status'
  final String operator;    // Operator: '==', '!=', '>', '<', 'in'
  final dynamic value;      // Filter value

  FilterExpression({
    required this.property,
    required this.operator,
    required this.value,
  });

  @override
  String toString() => '$property $operator $value';
}
```

#### 2.2 Implement hierarchy analyzer
**File**: `packages/tercen_json_path/lib/src/virtual_hierarchy_analyzer.dart` (new)

```dart
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// Analyzes JSONPath expressions to extract hierarchy requirements
class VirtualHierarchyAnalyzer {
  /// Analyze a JSONPath expression and extract what collections need to be fetched
  VirtualHierarchyPlan analyze(String expression) {
    final requirements = <CollectionRequirement>[];

    // Pattern: .collection[filter] or .collection[*]
    // Examples:
    // - .projects[?@.id == 'proj_456']
    // - .workflows[*]
    // - .teams[?@.name == 'Test']
    final segmentPattern = RegExp(
      r'\.(\w+)\[(?:(\*)|(?:\?@\.(\w+)\s*(==|!=|>|<|>=|<=)\s*[\'"]([^\'"]+)[\'"]))?\]',
    );

    String? prevCollection;
    int depth = 0;

    for (final match in segmentPattern.allMatches(expression)) {
      final collection = match.group(1)!;
      final isWildcard = match.group(2) != null;
      final filterProperty = match.group(3);
      final filterOperator = match.group(4);
      final filterValue = match.group(5);

      final filters = <FilterExpression>[];
      if (!isWildcard && filterProperty != null && filterOperator != null) {
        filters.add(FilterExpression(
          property: filterProperty,
          operator: filterOperator,
          value: filterValue,
        ));
      }

      // Only add if it's a known collection type
      if (_isVirtualCollection(collection)) {
        requirements.add(CollectionRequirement(
          collection: collection,
          parentCollection: prevCollection,
          filters: filters,
          depth: depth,
        ));

        prevCollection = collection;
        depth++;
      }
    }

    return VirtualHierarchyPlan(requirements);
  }

  bool _isVirtualCollection(String key) {
    return const [
      'projects',
      'teams',
      'workflows',
      'schemas',
      'files',
      'folders',
      'operators',
      'tasks',
      'users',
    ].contains(key);
  }
}
```

#### 2.3 Add tests for analyzer
**File**: `packages/tercen_json_path/test/virtual_hierarchy_analyzer_test.dart` (new)

```dart
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
      expect(plan.requirements[0].filters[0].value, 'proj_456');
    });

    test('extracts hierarchical collections', () {
      final plan = analyzer.analyze(
        r"$.projects[?@.id == 'proj_456'].workflows[*]"
      );

      expect(plan.requirements, hasLength(2));
      expect(plan.requirements[0].collection, 'projects');
      expect(plan.requirements[0].parentCollection, isNull);
      expect(plan.requirements[1].collection, 'workflows');
      expect(plan.requirements[1].parentCollection, 'projects');
    });

    test('extracts property filters', () {
      final plan = analyzer.analyze(r"$.projects[?@.name == 'Test']");

      expect(plan.requirements[0].filters[0].property, 'name');
      expect(plan.requirements[0].filters[0].value, 'Test');
      expect(plan.requirements[0].hasNonIdFilters, isTrue);
    });

    test('handles wildcards', () {
      final plan = analyzer.analyze(r"$.projects[*].workflows[*]");

      expect(plan.requirements, hasLength(2));
      expect(plan.requirements[0].filters, isEmpty);
      expect(plan.requirements[1].filters, isEmpty);
    });

    test('handles multi-level hierarchy', () {
      final plan = analyzer.analyze(
        r"$.teams[?@.id == 'team_123'].projects[?@.id == 'proj_456'].workflows[*]"
      );

      expect(plan.requirements, hasLength(3));
      expect(plan.requirements[0].collection, 'teams');
      expect(plan.requirements[1].collection, 'projects');
      expect(plan.requirements[2].collection, 'workflows');
    });
  });
}
```

#### 2.4 Export new classes
**File**: `packages/tercen_json_path/lib/json_path.dart`

```dart
export 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';
export 'package:tercen_json_path/src/virtual_hierarchy_analyzer.dart';
export 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart'; // Will create in Phase 3
```

### Deliverables
- ✅ `VirtualHierarchyPlan` data structures
- ✅ `VirtualHierarchyAnalyzer` extracts filters from JSONPath
- ✅ Comprehensive tests for pattern extraction
- ✅ Supports ID filters, property filters, wildcards, multi-level

### Files Created
- `lib/src/virtual_hierarchy_plan.dart`
- `lib/src/virtual_hierarchy_analyzer.dart`
- `test/virtual_hierarchy_analyzer_test.dart`

---

## Phase 3: Virtual Hierarchy Resolver (2-3 days)

### Goal
Create resolver interface and integrate with Node for lazy collection fetching.

### Tasks

#### 3.1 Create resolver interface
**File**: `packages/tercen_json_path/lib/src/virtual_hierarchy_resolver.dart` (new)

```dart
import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// Extended resolver that supports virtual hierarchy fetching
abstract class VirtualHierarchyResolver extends RefIdResolver {
  /// Pre-fetch all collections required by the hierarchy plan
  /// Called once before JSONPath evaluation begins
  Future<void> prefetchHierarchy(VirtualHierarchyPlan plan, dynamic rootJson);

  /// Resolve a collection with context
  /// Called during JSONPath evaluation when a collection is accessed
  Future<List<Map<String, dynamic>>> resolveCollection(
    String collection,
    VirtualHierarchyContext context,
  );
}

/// Context for resolving a collection
class VirtualHierarchyContext {
  final String? parentCollection;   // Parent collection name
  final String? parentId;            // Parent document ID
  final Map<String, dynamic> metadata; // Additional context

  VirtualHierarchyContext({
    this.parentCollection,
    this.parentId,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'VirtualHierarchyContext(parent: $parentCollection/$parentId)';
}
```

#### 3.2 Update Node to support resolver
**File**: `packages/tercen_json_path/lib/src/node.dart`

```dart
import 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart';

class Node<T extends Object?> {
  // Add resolver field
  final VirtualHierarchyResolver? _resolver;
  final VirtualHierarchyContext? _context;

  // Update constructors
  Node(this.value, {VirtualHierarchyResolver? resolver, VirtualHierarchyContext? context})
      : parent = null,
        key = null,
        index = null,
        _resolver = resolver,
        _context = context;

  Node._(
    this.value,
    this.parent, {
    this.key,
    this.index,
    VirtualHierarchyResolver? resolver,
    VirtualHierarchyContext? context,
  }) : _resolver = resolver ?? parent?._resolver,
       _context = context ?? parent?._context;

  // Update child method
  Future<Node?> child(String key) async {
    final v = value;

    // Try to get from existing data first (fast path)
    if (v is Map && v.containsKey(key)) {
      return _child(v, key);
    }

    // Try virtual collection resolution (slow path)
    if (_resolver != null && _isVirtualCollection(key)) {
      final context = VirtualHierarchyContext(
        parentCollection: _inferCollectionFromNode(),
        parentId: _extractIdFromNode(),
      );

      final docs = await _resolver!.resolveCollection(key, context);

      if (docs.isNotEmpty) {
        // Create virtual child with fetched data
        return _createVirtualChild(key, docs);
      }
    }

    return null;
  }

  bool _isVirtualCollection(String key) {
    return const [
      'projects',
      'teams',
      'workflows',
      'schemas',
      'files',
      'folders',
      'operators',
      'tasks',
      'users',
    ].contains(key);
  }

  String? _inferCollectionFromNode() {
    // Try to infer collection type from node data
    final v = value;
    if (v is Map) {
      final kind = v['kind'] as String?;
      return _mapKindToCollection(kind);
    }
    return null;
  }

  String? _mapKindToCollection(String? kind) {
    if (kind == null) return null;

    switch (kind) {
      case 'Project': return 'projects';
      case 'Team': return 'teams';
      case 'Workflow': return 'workflows';
      default: return null;
    }
  }

  String? _extractIdFromNode() {
    final v = value;
    if (v is Map) {
      return v['id'] as String?;
    }
    return null;
  }

  Node _createVirtualChild(String key, List<Map<String, dynamic>> docs) {
    // Inject the fetched documents into parent's value
    final parentValue = value as Map;
    final updatedValue = Map<String, dynamic>.from(parentValue);
    updatedValue[key] = docs;

    // Return the child node
    return Node._(
      docs,
      this,
      key: key,
      resolver: _resolver,
      context: _context,
    );
  }

  // Update _child and _element to propagate resolver
  Node _element(List list, int index) =>
      Node._(list[index], this, index: index, resolver: _resolver, context: _context);

  Node _child(Map map, String key) =>
      Node._(map[key], this, key: key, resolver: _resolver, context: _context);
}
```

#### 3.3 Update JsonPath to use analyzer and resolver
**File**: `packages/tercen_json_path/lib/src/json_path_internal.dart`

```dart
import 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

class JsonPathInternal implements JsonPath {
  JsonPathInternal(
    this.expression,
    this.selector, {
    this.resolver,
    this.hierarchyPlan,
  });

  final Selector selector;
  final String expression;
  final VirtualHierarchyResolver? resolver;
  final VirtualHierarchyPlan? hierarchyPlan;

  @override
  Stream<JsonPathMatch> read(json) async* {
    // Prefetch if we have a resolver and plan
    if (resolver != null && hierarchyPlan != null) {
      await resolver!.prefetchHierarchy(hierarchyPlan!, json);
    }

    // Create root node with resolver
    final rootNode = Node(
      json,
      resolver: resolver,
      context: VirtualHierarchyContext(),
    );

    // Evaluate
    yield* selector(SingularNodeStream(rootNode)).map(NodeMatch.new);
  }

  @override
  Stream<Object?> readValues(json) => read(json).map((node) => node.value);
}
```

#### 3.4 Update parser to create plan
**File**: `packages/tercen_json_path/lib/src/json_path_parser.dart`

```dart
import 'package:tercen_json_path/src/virtual_hierarchy_analyzer.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart';

class JsonPathParser {
  final _analyzer = VirtualHierarchyAnalyzer();

  JsonPath parse(String expression, {RefIdResolver? resolver}) {
    // Parse expression to selector
    final parser = resolver != null
        ? JsonPathGrammarDefinition(
            FunFactory(_stdFun.followedBy(const [])),
            resolver,
          ).build()
        : _parser;

    final expr = parser.parse(expression).value;
    final Selector selector = (NodeStream nodes) {
      return MultiNodeStream((() async* {
        await for (final node in nodes) {
          final result = await expr.call(node);
          yield* result;
        }
      })());
    };

    // Analyze hierarchy requirements if we have a virtual resolver
    VirtualHierarchyPlan? plan;
    if (resolver is VirtualHierarchyResolver) {
      plan = _analyzer.analyze(expression);
    }

    return JsonPathInternal(
      expression,
      selector,
      resolver: resolver is VirtualHierarchyResolver ? resolver : null,
      hierarchyPlan: plan,
    );
  }
}
```

### Deliverables
- ✅ `VirtualHierarchyResolver` interface defined
- ✅ Node supports lazy collection fetching
- ✅ JsonPath creates hierarchy plan on construction
- ✅ Prefetch called before evaluation

### Files Modified
- `lib/src/node.dart` (major updates)
- `lib/src/json_path_internal.dart`
- `lib/src/json_path_parser.dart`

### Files Created
- `lib/src/virtual_hierarchy_resolver.dart`

---

## Phase 4: Query Service Integration (2-3 days)

### Goal
Implement `VirtualHierarchyResolver` for CouchDB/QueryService and wire up with existing infrastructure.

### Tasks

#### 4.1 Create CouchDB resolver implementation
**File**: `sci_api_service/lib/src/query/couch_db_virtual_hierarchy_resolver.dart` (new)

```dart
import 'package:tercen_json_path/json_path.dart';
import 'package:sci_base/sci_service.dart' as service;
import 'package:sci_api_service/src/query/scope_inference.dart';
import 'package:sci_api_service/src/query/permission_aware_mango_builder.dart';

/// Virtual hierarchy resolver that fetches from CouchDB
class CouchDBVirtualHierarchyResolver implements VirtualHierarchyResolver {
  final Function queryExecutor; // Function to execute Mango queries
  final service.AclContext aclContext;
  final ScopeInference scopeInference;
  final PermissionAwareMangoBuilder queryBuilder;

  // Cache for prefetched collections
  final Map<String, List<Map<String, dynamic>>> _cache = {};

  CouchDBVirtualHierarchyResolver({
    required this.queryExecutor,
    required this.aclContext,
    required this.scopeInference,
    required this.queryBuilder,
  });

  @override
  Future<void> prefetchHierarchy(
    VirtualHierarchyPlan plan,
    dynamic rootJson,
  ) async {
    // Execute queries for all requirements in parallel
    final futures = <Future>[];

    for (final req in plan.requirements) {
      futures.add(_prefetchCollection(req));
    }

    await Future.wait(futures);
  }

  Future<void> _prefetchCollection(CollectionRequirement req) async {
    // Build scope for this collection
    final scope = Scope(
      userId: aclContext.username,
      teamId: req.parentCollection == 'teams' ? req.idFilter : null,
      projectId: req.parentCollection == 'projects' ? req.idFilter : null,
      documentKinds: _mapCollectionToKinds(req.collection),
    );

    // Build query
    final queries = queryBuilder.buildQueries(scope, aclContext);

    // Add property filters from JSONPath
    for (final query in queries) {
      final selector = query['selector'] as Map<String, dynamic>;

      for (final filter in req.filters) {
        if (filter.property != 'id') {
          selector[filter.property] = {
            '\$${filter.operator}': filter.value
          };
        } else if (filter.property == 'id') {
          selector['_id'] = {'\$eq': filter.value};
        }
      }
    }

    // Execute queries
    final allDocs = <Map<String, dynamic>>[];
    for (final query in queries) {
      final docs = await queryExecutor(query);
      allDocs.addAll(docs.map((d) => d.toJson() as Map<String, dynamic>));
    }

    // Cache results
    final cacheKey = _buildCacheKey(req);
    _cache[cacheKey] = allDocs;
  }

  @override
  Future<List<Map<String, dynamic>>> resolveCollection(
    String collection,
    VirtualHierarchyContext context,
  ) async {
    // Return from cache
    final cacheKey = _buildCacheKeyFromContext(collection, context);
    final cached = _cache[cacheKey];

    if (cached != null) {
      // Filter by parent ID if specified
      if (context.parentId != null) {
        final parentField = _getParentField(context.parentCollection);
        return cached.where((doc) => doc[parentField] == context.parentId).toList();
      }
      return cached;
    }

    return [];
  }

  @override
  Future<Map<String, dynamic>?> dereference(String refId, String targetKind) async {
    // Existing dereferencing logic (not implemented here)
    throw UnimplementedError('Dereference not implemented in this resolver');
  }

  String _buildCacheKey(CollectionRequirement req) {
    return '${req.parentCollection ?? 'root'}:${req.collection}:${req.filters.map((f) => f.toString()).join(',')}';
  }

  String _buildCacheKeyFromContext(String collection, VirtualHierarchyContext context) {
    return '${context.parentCollection ?? 'root'}:$collection:';
  }

  String _getParentField(String? parentCollection) {
    switch (parentCollection) {
      case 'projects': return 'projectId';
      case 'teams': return 'teamId';
      case 'workflows': return 'workflowId';
      default: return 'parentId';
    }
  }

  List<String> _mapCollectionToKinds(String collection) {
    switch (collection) {
      case 'workflows': return ['Workflow'];
      case 'projects': return ['Project'];
      case 'teams': return ['Team'];
      case 'schemas': return ['TableSchema', 'CubeQueryTableSchema', 'ComputedTableSchema'];
      case 'files': return ['FileDocument'];
      case 'folders': return ['FolderDocument'];
      case 'operators': return ['Operator', 'GitOperator', 'DockerOperator', 'ROperator', 'WebAppOperator'];
      case 'tasks': return ['Task', 'ProjectTask', 'RunComputationTask', /* ... all task types */];
      case 'users': return ['User'];
      default: return [];
    }
  }
}
```

#### 4.2 Update MockQueryService
**File**: `sci_api_service/lib/src/query/mock_query_service.dart`

Add support for using `VirtualHierarchyResolver`:

```dart
class MockQueryService {
  final List<PersistentObject> mockDocuments;
  final bool useVirtualHierarchy; // NEW flag

  MockQueryService(
    this.mockDocuments, {
    this.useVirtualHierarchy = true, // Enable by default
  });

  Stream<PersistentObject> query(
    String jsonPath,
    int limit, {
    required service.AclContext aclContext,
  }) async* {
    if (useVirtualHierarchy) {
      // Use virtual hierarchy resolver
      final resolver = _createVirtualHierarchyResolver(aclContext);
      final path = JsonPath(jsonPath, resolver: resolver);

      // Start with empty root
      final results = await path.read({}).toList();

      // Convert matches back to PersistentObject
      for (final match in results) {
        final json = match.value as Map<String, dynamic>;
        yield _jsonToPersistentObject(json);
      }
    } else {
      // Legacy: use existing full pipeline
      // ... existing code
    }
  }

  VirtualHierarchyResolver _createVirtualHierarchyResolver(
    service.AclContext aclContext,
  ) {
    return MockVirtualHierarchyResolver(
      documents: mockDocuments,
      aclContext: aclContext,
    );
  }
}
```

#### 4.3 Create MockVirtualHierarchyResolver
**File**: `sci_api_service/test/query/helpers/mock_virtual_hierarchy_resolver.dart` (new)

```dart
class MockVirtualHierarchyResolver implements VirtualHierarchyResolver {
  final List<PersistentObject> documents;
  final service.AclContext aclContext;
  final Map<String, List<Map<String, dynamic>>> _cache = {};

  MockVirtualHierarchyResolver({
    required this.documents,
    required this.aclContext,
  });

  @override
  Future<void> prefetchHierarchy(
    VirtualHierarchyPlan plan,
    dynamic rootJson,
  ) async {
    for (final req in plan.requirements) {
      await _prefetchCollection(req);
    }
  }

  Future<void> _prefetchCollection(CollectionRequirement req) async {
    // Filter documents by kind
    final kinds = _mapCollectionToKinds(req.collection);
    var filtered = documents.where((doc) {
      final json = doc.toJson();
      return kinds.contains(json['kind']);
    });

    // Apply parent filters
    if (req.parentCollection != null && req.idFilter != null) {
      final parentField = _getParentField(req.parentCollection);
      filtered = filtered.where((doc) {
        final json = doc.toJson();
        return json[parentField] == req.idFilter;
      });
    }

    // Apply property filters
    for (final filter in req.filters) {
      filtered = filtered.where((doc) {
        final json = doc.toJson();
        final value = json[filter.property];
        return _applyFilter(value, filter.operator, filter.value);
      });
    }

    // Apply ACL filtering
    filtered = filtered.where((doc) {
      final json = doc.toJson();
      final acl = json['acl'] as Map?;
      final owner = acl?['owner'] as String?;
      return aclContext.aclOwners.contains(owner);
    });

    // Cache
    final cacheKey = _buildCacheKey(req);
    _cache[cacheKey] = filtered.map((d) => d.toJson() as Map<String, dynamic>).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> resolveCollection(
    String collection,
    VirtualHierarchyContext context,
  ) async {
    final cacheKey = _buildCacheKeyFromContext(collection, context);
    return _cache[cacheKey] ?? [];
  }

  @override
  Future<Map<String, dynamic>?> dereference(String refId, String targetKind) async {
    return null; // Not needed for mock
  }

  bool _applyFilter(dynamic value, String operator, dynamic filterValue) {
    switch (operator) {
      case '==': return value == filterValue;
      case '!=': return value != filterValue;
      case '>': return (value as num) > (filterValue as num);
      case '<': return (value as num) < (filterValue as num);
      default: return false;
    }
  }

  // ... helper methods similar to CouchDB resolver
}
```

### Deliverables
- ✅ `CouchDBVirtualHierarchyResolver` implemented
- ✅ `MockVirtualHierarchyResolver` for testing
- ✅ Integration with existing query infrastructure
- ✅ ACL filtering maintained
- ✅ Property filters applied correctly

### Files Created
- `sci_api_service/lib/src/query/couch_db_virtual_hierarchy_resolver.dart`
- `sci_api_service/test/query/helpers/mock_virtual_hierarchy_resolver.dart`

### Files Modified
- `sci_api_service/lib/src/query/mock_query_service.dart`

---

## Phase 5: Test Migration (1-2 days)

### Goal
Update failing tests to use virtual hierarchy resolver and verify all tests pass.

### Tasks

#### 5.1 Update hierarchical query tests
**File**: `sci_api_service/test/query/mock/hierarchical_queries_test.dart`

Enable virtual hierarchy for all tests:

```dart
void main() {
  group('Hierarchical Queries with Virtual Hierarchy', () {
    late MockQueryService mockService;
    late service.AclContext context;

    setUp(() {
      context = service.AclContext(
        username: 'user123',
        aclOwners: ['user123', 'shared-team'],
      );
    });

    test('queries all workflows in specific project', () async {
      final mockDocuments = [
        createWorkflow(id: 'wf_1', projectId: 'proj_456', ownerId: 'user123'),
        createWorkflow(id: 'wf_2', projectId: 'proj_456', ownerId: 'shared-team'),
        createProject(id: 'proj_456', name: 'Test Project', ownerId: 'user123'),
      ];
      mockService = MockQueryService(
        mockDocuments,
        useVirtualHierarchy: true, // Enable virtual hierarchy
      );

      final results = await mockService
          .query(r"$.projects[?@.id == 'proj_456'].workflows[*]", 10, aclContext: context)
          .toList();

      expect(results, hasLength(2)); // Should now pass!
      expect(results.every((w) => w.toJson()['projectId'] == 'proj_456'), isTrue);
    });

    // ... update all 17 tests similarly
  });
}
```

#### 5.2 Verify basic queries still work
**File**: `sci_api_service/test/query/mock/basic_queries_test.dart`

Ensure backward compatibility:

```dart
test('basic wildcard query works with virtual hierarchy', () async {
  mockService = MockQueryService(
    mockDocuments,
    useVirtualHierarchy: true,
  );

  final results = await mockService
      .query(r'$.workflows[*]', 10, aclContext: context)
      .toList();

  expect(results, hasLength(3));
});
```

#### 5.3 Add new test cases for property filters
**File**: `sci_api_service/test/query/mock/property_filter_queries_test.dart` (new)

```dart
void main() {
  group('Property Filter Queries', () {
    test('filters projects by name', () async {
      final mockDocuments = [
        createProject(id: 'proj_1', name: 'Test Project', ownerId: 'user123'),
        createProject(id: 'proj_2', name: 'Other Project', ownerId: 'user123'),
        createWorkflow(id: 'wf_1', projectId: 'proj_1', ownerId: 'user123'),
      ];
      mockService = MockQueryService(mockDocuments, useVirtualHierarchy: true);

      final results = await mockService
          .query(r"$.projects[?@.name == 'Test Project'].workflows[*]", 10, aclContext: context)
          .toList();

      expect(results, hasLength(1));
      expect(results[0].toJson()['id'], 'wf_1');
    });

    // ... more property filter tests
  });
}
```

#### 5.4 Run full test suite
```bash
cd sci_api_service
dart test test/query/
```

### Deliverables
- ✅ All 17 hierarchical tests passing
- ✅ All 13 basic tests still passing
- ✅ New property filter tests added and passing
- ✅ No regressions in existing functionality

### Files Modified
- `sci_api_service/test/query/mock/hierarchical_queries_test.dart`
- `sci_api_service/test/query/mock/basic_queries_test.dart`

### Files Created
- `sci_api_service/test/query/mock/property_filter_queries_test.dart`

---

## Testing Strategy

### Unit Tests (per phase)
- **Phase 1**: Async node access
- **Phase 2**: Hierarchy analyzer pattern extraction
- **Phase 3**: Virtual collection resolution
- **Phase 4**: Query execution and filtering
- **Phase 5**: End-to-end integration

### Integration Tests
- Full JSONPath evaluation with virtual hierarchy
- ACL filtering correctness
- Multi-level hierarchy traversal
- Property filter application

### Performance Tests
- Measure query count (should be minimal)
- Measure prefetch time
- Compare with/without virtual hierarchy

---

## Success Criteria

✅ **All async**: Node API fully async
✅ **Filter look-ahead**: Parser extracts all filters before execution
✅ **Optimal fetching**: Only required collections fetched with filters applied
✅ **Tests passing**: 30/30 tests pass (13 basic + 17 hierarchical)
✅ **Property filters**: New tests for property filters pass
✅ **No regressions**: Existing functionality unchanged
✅ **Performance**: Query count optimal, no over-fetching

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Async Node API | 1-2 days | None |
| Phase 2: Hierarchy Plan & Analysis | 2-3 days | Phase 1 |
| Phase 3: Virtual Hierarchy Resolver | 2-3 days | Phase 2 |
| Phase 4: Query Service Integration | 2-3 days | Phase 3 |
| Phase 5: Test Migration | 1-2 days | Phase 4 |

**Total: 8-13 days** (approximately 2-3 weeks)

---

## Risk Mitigation

### Key Risks

1. **Async breaking changes**
   - Mitigation: Comprehensive test coverage, incremental rollout
   - Fallback: Feature flag to disable virtual hierarchy

2. **Complex filter expressions**
   - Mitigation: Start with simple operators (==, !=), expand gradually
   - Fallback: Fetch all, filter in memory for complex expressions

3. **Performance regressions**
   - Mitigation: Benchmark at each phase
   - Fallback: Optimize caching, add query batching

4. **Parent-child relationship inference**
   - Mitigation: Explicit relationship mapping in resolver
   - Fallback: Use VirtualHierarchyBuilder for complex nesting

---

## Next Steps

1. ✅ Review and approve this plan
2. Begin Phase 1: Async Node API
3. Regular check-ins after each phase
4. Update HIERARCHICAL_QUERY_LIMITATION.md when complete
