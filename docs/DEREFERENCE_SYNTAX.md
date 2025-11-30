# @ Dereferencing Syntax

## Overview

The `@` operator is a Tercen-specific extension to RFC 9535 JSONPath that enables **async dereferencing** of RefId references to their target documents.

This is designed for scenarios where JSON documents contain references (like foreign keys) that need to be resolved from external data stores like CouchDB.

## Syntax

```
fieldName@TargetKind
```

- **fieldName**: The field containing the RefId value (e.g., `operatorId`, `projectId`)
- **TargetKind**: The expected document kind/type (e.g., `Operator`, `Project`, `User`)

## Examples

### Basic Dereferencing

```dart
// JSON document
{
  "workflow": {
    "id": "wf_1",
    "projectId": "proj_abc"  // RefId to a Project document
  }
}

// Query
$.workflow.projectId@Project

// Result: The entire Project document
{
  "kind": "Project",
  "id": "proj_abc",
  "name": "My Analysis Project",
  "owner": "alice"
}
```

### Dereferencing in Arrays

```dart
// JSON document
{
  "workflow": {
    "steps": [
      {"id": "step_1", "operatorId": "op_mean"},
      {"id": "step_2", "operatorId": "op_pca"}
    ]
  }
}

// Query
$.workflow.steps[*].operatorId@Operator

// Result: Array of Operator documents
[
  {"kind": "Operator", "id": "op_mean", "name": "Mean", "category": "Math"},
  {"kind": "Operator", "id": "op_pca", "name": "PCA", "category": "ML"}
]
```

### Property Access After Dereferencing

```dart
// Query - chain property access after @
$.workflow.steps[*].operatorId@Operator.name

// Result: Array of operator names
["Mean", "PCA"]
```

### Multiple Dereferences

```dart
// Query - dereference multiple fields
$.workflow.projectId@Project.name
$.workflow.userId@User.email

// Can be used together in queries
```

## Implementation

### 1. Define a RefIdResolver

Create a class implementing the `RefIdResolver` interface:

```dart
import 'package:tercen_json_path/src/ref_id_resolver.dart';

class CouchDBResolver implements RefIdResolver {
  final CouchDBClient db;

  CouchDBResolver(this.db);

  @override
  Future<Map<String, dynamic>?> dereference(String refId, String targetKind) async {
    try {
      // Fetch document from CouchDB
      final doc = await db.get(refId);

      // Optional: verify the document kind matches
      if (doc['kind'] != targetKind) {
        return null; // Kind mismatch
      }

      return doc;
    } catch (e) {
      // Document not found or error
      return null;
    }
  }
}
```

### 2. Use @ in Queries

```dart
import 'package:tercen_json_path/json_path.dart';

// Create resolver
final resolver = CouchDBResolver(couchDBClient);

// Parse JSONPath with @ syntax
final path = JsonPath(
  r'$.workflows[*].steps[*].operatorId@Operator.category',
  resolver: resolver,
);

// Execute query (async)
final categories = await path.readValues(jsonData).toList();
```

## Behavior

### Successful Dereferencing

When a RefId is successfully resolved:
1. The resolver's `dereference()` method is called
2. The returned document is wrapped in a new Node
3. Further path segments (like `.name`) are applied to the dereferenced document

### Failed Dereferencing

When dereferencing fails (document not found, kind mismatch, or error):
1. The resolver returns `null`
2. That particular node is **silently skipped** (not included in results)
3. Processing continues for other nodes

```dart
// If step_2's operator doesn't exist, it's skipped
$.steps[*].operatorId@Operator.name
// Result: ["Mean", "PCA"]  // step_3's missing operator is not in results
```

### Without Resolver

If no resolver is provided:
```dart
final path = JsonPath(r'$.field@Type'); // No resolver parameter

// The @ syntax is parsed but dereferencing is skipped
// Result: empty (no documents resolved)
```

## Performance Considerations

### Async Evaluation

Dereferencing is **async** - each RefId lookup may require network I/O:

```dart
// This could result in N database queries
$.workflows[*].steps[*].operatorId@Operator
```

### Optimization Strategies

1. **Batch Fetching**: Implement batching in your resolver
   ```dart
   class BatchingResolver implements RefIdResolver {
     final _cache = <String, Map<String, dynamic>>{};

     Future<void> prefetch(List<String> refIds) async {
       // Fetch multiple documents in one request
       final docs = await db.bulkGet(refIds);
       _cache.addAll(docs);
     }

     @override
     Future<Map<String, dynamic>?> dereference(String refId, String kind) async {
       return _cache[refId] ?? await db.get(refId);
     }
   }
   ```

2. **Caching**: Cache resolved documents in the resolver

3. **Parallel Resolution**: The implementation uses async streams, so multiple resolutions can happen concurrently

## Limitations

### Current Limitations

1. **@ in Filter Expressions** (Not yet supported)
   ```dart
   // This doesn't work yet
   $.steps[?@.operatorId@Operator.category == 'ML']
   ```

   **Workaround**: Dereference first, filter after
   ```dart
   final ops = await JsonPath(r'$.steps[*].operatorId@Operator').read(data).toList();
   final mlOps = ops.where((op) => (op.value as Map)['category'] == 'ML');
   ```

2. **Nested @ Chains** (Not tested)
   ```dart
   // May or may not work
   $.workflow.projectId@Project.ownerId@User.name
   ```

### Design Limitations

- **No Compile-Time Validation**: The `TargetKind` is just a string, not validated at parse time
- **Path Information Lost**: Dereferenced nodes are created as root nodes, losing parent/key information
- **No Circular Reference Detection**: Be careful with recursive dereferences

## Best Practices

### 1. Use Specific Kind Names

```dart
// Good: Specific kind
$.field@Operator

// Bad: Generic kind
$.field@Document
```

### 2. Handle Nulls in Resolver

```dart
@override
Future<Map<String, dynamic>?> dereference(String refId, String kind) async {
  // Always return null for failures, never throw
  try {
    return await db.get(refId);
  } catch (e) {
    return null; // Gracefully handle missing documents
  }
}
```

### 3. Chain Properties for Efficiency

```dart
// Efficient: Only get what you need
$.steps[*].operatorId@Operator.name

// Less efficient: Dereference entire documents when you only need a field
$.steps[*].operatorId@Operator
// Then extract .name in Dart code
```

### 4. Consider Query Order

```dart
// Better: Dereference after filtering
$.steps[?@.status == 'active'][*].operatorId@Operator

// Worse: Filter after dereferencing (more DB queries)
$.steps[*].operatorId@Operator[?@.category == 'ML']
```

## Testing

Use a mock resolver for testing:

```dart
class MockResolver implements RefIdResolver {
  final Map<String, Map<String, dynamic>> _store;

  MockResolver(this._store);

  @override
  Future<Map<String, dynamic>?> dereference(String refId, String kind) async {
    await Future.delayed(Duration(milliseconds: 10)); // Simulate network
    final doc = _store[refId];
    if (doc?['kind'] != kind) return null;
    return doc;
  }
}

// Test
final resolver = MockResolver({
  'op_1': {'kind': 'Operator', 'name': 'PCA'},
});

final path = JsonPath(r'$.operatorId@Operator.name', resolver: resolver);
final result = await path.readValues({'operatorId': 'op_1'}).single;
expect(result, 'PCA');
```

## See Also

- [RefIdResolver API](../lib/src/ref_id_resolver.dart)
- [DereferenceSelector Implementation](../lib/src/grammar/dereference_selector.dart)
- [Test Examples](../test/dereference_test.dart)
