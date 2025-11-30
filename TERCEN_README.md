# Tercen JSONPath Fork

> **Tercen-specific fork** of [f3ath/jessie](https://github.com/f3ath/jessie) with async/stream architecture and `@` dereferencing syntax for RefId resolution.

## Tercen Extensions

This fork extends the standard RFC 9535 JSONPath implementation with features specifically designed for Tercen's workflow and operator system:

### 🚀 Key Features

1. **Full Async/Stream Architecture**
   - All selectors use `Stream<Node>` for efficient lazy evaluation
   - Filter expressions support async evaluation
   - Ready for large-scale data processing

2. **@ Dereferencing Syntax** ⭐
   - Resolve RefId references to their target documents
   - Async document lookup from CouchDB or other sources
   - Syntax: `fieldName@TargetKind`

3. **Graceful Error Handling**
   - Missing references are silently skipped
   - Continues processing remaining nodes
   - No exceptions for missing documents

## Quick Start

### Installation

```yaml
dependencies:
  tercen_json_path:
    git:
      url: https://github.com/tercen/json_path.git
      ref: tercen-extensions
```

### Basic @ Dereferencing

```dart
import 'package:tercen_json_path/json_path.dart';

// 1. Implement a RefIdResolver
class CouchDBResolver implements RefIdResolver {
  final CouchDBClient db;
  CouchDBResolver(this.db);

  @override
  Future<Map<String, dynamic>?> dereference(String refId, String targetKind) async {
    return await db.get(refId);
  }
}

// 2. Use @ syntax in queries
final resolver = CouchDBResolver(myDb);
final path = JsonPath(
  r'$.workflows[*].steps[*].operatorId@Operator.name',
  resolver: resolver,
);

// 3. Execute (returns Stream)
final operatorNames = await path.readValues(workflowData).toList();
print(operatorNames); // ['Mean', 'PCA', 'Plot']
```

## @ Syntax Examples

### Get Referenced Document

```dart
// Dereference a single RefId
$.workflow.projectId@Project

// Result: The entire Project document
```

### Dereference in Arrays

```dart
// Dereference for each array element
$.workflow.steps[*].operatorId@Operator

// Result: Array of Operator documents
```

### Chain Property Access

```dart
// Access properties after dereferencing
$.workflow.steps[*].operatorId@Operator.category

// Result: ['Math', 'ML', 'Visualization']
```

### Multiple Types

```dart
// Dereference different types in same query
$.workflow.projectId@Project.name          // → "My Project"
$.workflow.userId@User.email                // → "user@example.com"
$.workflow.steps[*].operatorId@Operator.name // → ['Op1', 'Op2', ...]
```

## API Differences from Upstream

### Async Results

```dart
// ❌ Old (upstream)
Iterable<JsonPathMatch> results = JsonPath(expr).read(json);

// ✅ New (Tercen fork)
Stream<JsonPathMatch> results = JsonPath(expr).read(json);
await for (final match in results) {
  print(match.value);
}

// Or collect to list
final list = await JsonPath(expr).read(json).toList();
```

### Optional Resolver Parameter

```dart
// Without resolver - standard JSONPath only
final path1 = JsonPath(r'$.field');

// With resolver - enables @ dereferencing
final path2 = JsonPath(r'$.field@Type', resolver: myResolver);
```

## Documentation

- **[@ Dereferencing Guide](docs/DEREFERENCE_SYNTAX.md)** - Complete @ syntax reference
- **[Examples](example/dereference_example.dart)** - Working code examples
- **[Tests](test/dereference_test.dart)** - Test suite showing all features

## Architecture

### Async/Stream Pipeline

```
JsonPath Expression
  ↓
Parser (with optional RefIdResolver)
  ↓
Selector: Stream<Node> Function(Stream<Node>)
  ↓
Async Evaluation
  ├─ Filter: await filter.call(node)
  ├─ @ Operator: await resolver.dereference(refId, kind)
  └─ Property Access: node.children
  ↓
Stream<JsonPathMatch>
```

### Selector Types (All Async)

- `childSelector` - Property access (`.field`)
- `arrayIndexSelector` - Array element (`[0]`)
- `arraySliceSelector` - Array slice (`[0:5]`)
- `filterSelector` - Filters with async predicates (`[?@.x > 10]`)
- `unionSelector` - Multiple selectors (`[0, 'name']`)
- `wildcardSelector` - All children (`[*]` or `.*`)
- `recursiveSelector` - Recursive descent (`..`)
- **`dereferenceSelector`** ⭐ - RefId dereferencing (`field@Type`)

## Performance

### Async Dereferencing

Each `@` operator triggers an async lookup:

```dart
// This could result in 100 CouchDB queries
$.workflows[*].steps[*].operatorId@Operator  // If 100 steps total
```

**Optimization**: Implement batching in your resolver:

```dart
class BatchingResolver implements RefIdResolver {
  @override
  Future<Map<String, dynamic>?> dereference(String refId, String kind) async {
    // Collect multiple refIds and fetch in bulk
    return await _batchFetch([refId])[refId];
  }
}
```

### Stream Benefits

- **Lazy evaluation**: Results computed on-demand
- **Memory efficient**: No need to materialize entire result sets
- **Cancellable**: Can stop iteration early

## Advanced Features

### @ Dereferencing in Filter Expressions ✅

Filter expressions now support @ dereferencing with chained property access:

```dart
// ✅ Filter by dereferenced properties
$.steps[?@.operatorId@Operator.category == 'ML']

// ✅ Chain multiple segments after dereferencing
$.steps[?@.operatorId@Operator.config.maxIterations > 100]

// ✅ Complex filter conditions
$.workflows[0].steps[?@.operatorId@Operator.category == 'ML' && @.status == 'active']
```

## Known Limitations

1. **Path Information** - Dereferenced nodes lose parent/key information
   (created as root nodes)

2. **No Circular Reference Detection** - Recursive dereferences not prevented

3. **Nested @ Chains** - Not extensively tested
   ```dart
   // May work but not guaranteed
   $.projectId@Project.ownerId@User.name
   ```

## Development

### Run Tests

```bash
dart test
```

### Run @ Dereferencing Tests

```bash
dart test test/dereference_test.dart
```

### Run Example

```bash
dart run example/dereference_example.dart
```

## Contributing

This is a Tercen-specific fork. For contributions:

- **Tercen features**: Open PRs on this repository
- **RFC 9535 compliance**: Consider contributing to [upstream](https://github.com/f3ath/jessie)

## License

MIT License - Same as upstream [f3ath/jessie](https://github.com/f3ath/jessie)

## Credits

- **Upstream**: [f3ath/jessie](https://github.com/f3ath/jessie) - Original RFC 9535 implementation
- **Tercen Extensions**: Async/stream architecture and @ dereferencing syntax

---

For standard JSONPath usage without Tercen extensions, see the [original README](https://github.com/f3ath/jessie) or the RFC 9535 specification.
