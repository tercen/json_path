# DocRefId Design Document

## Overview

This document outlines a future enhancement to the `tercen_json_path` library to support **in-document reference resolution** via a new `DocRefId` annotation and `@@` JSONPath syntax.

## Problem Statement

Currently, the library supports two types of property resolution:

1. **RefId (`@` syntax)**: Resolves references to **external persistent objects** stored in CouchDB
   - Example: `projectId@Project` fetches the Project document from the database

2. **Virtual Properties**: Computes derived properties from data within the same document
   - Example: `parentSteps` traverses links/steps in a Workflow

There's a gap for **in-document references** - fields that reference other objects within the same document by ID:

| Field | Source | Target | Location |
|-------|--------|--------|----------|
| `Step.groupId` | Any Step | GroupStep | Same Workflow |
| `Link.inputId` | Link | InputPort | Same Workflow |
| `Link.outputId` | Link | OutputPort | Same Workflow |

These are currently resolved imperatively in Dart code but cannot be dereferenced in JSONPath queries.

## Proposed Solution

### 1. DocRefId Annotation

Add a new annotation for marking in-document references in model definitions:

```dart
// In sci_api_gen/lib/api_lib.dart

/// Marks a field as a reference to another object within the same document.
/// Unlike RefId which references external persistent objects, DocRefId
/// references objects embedded in the same document tree.
class DocRefId {
  /// The kind/type of the target object (e.g., 'GroupStep', 'InputPort')
  final String kind;

  /// Optional JSONPath hint for where to search within the document.
  /// If null, the entire document tree is searched.
  /// Example: r'$.steps[*]' to search only in steps array
  final String? searchPath;

  const DocRefId(this.kind, {this.searchPath});
}
```

### 2. Model Annotations

Apply the annotation to relevant model fields:

```dart
// In sci_api/lib/src/api/model/step.dart
@GrpcOneOf(118)
class Step extends IdObject {
  @DocRefId('GroupStep', searchPath: r'$.steps[*]')
  String? groupId;
  // ...
}

// In sci_api/lib/src/api/model/link.dart
@GrpcOneOf(56)
class Link extends IdObject {
  @DocRefId('InputPort', searchPath: r'$.steps[*].inputs[*]')
  String? inputId;

  @DocRefId('OutputPort', searchPath: r'$.steps[*].outputs[*]')
  String? outputId;
}
```

### 3. JSONPath Syntax: `@@`

Use `@@` (double-at) to distinguish in-document dereferencing from external dereferencing:

| Syntax | Meaning | Resolution |
|--------|---------|------------|
| `fieldName@Kind` | External reference | Fetch from database via RefIdResolver |
| `fieldName@@Kind` | Document reference | Find in document tree via DocRefIdResolver |

#### Examples

```jsonpath
# Resolve groupId to the actual GroupStep object
$.steps[?@.groupId != ''].groupId@@GroupStep

# Get the name of the group a step belongs to
$.steps[?@.id == 'step1'].groupId@@GroupStep.name

# Resolve link's input port
$.links[*].inputId@@InputPort

# Get the step that owns a link's input port
$.links[*].inputId@@InputPort.???  # Need parent access

# Filter steps by their group's properties
$.steps[?@.groupId@@GroupStep.name == 'Analysis']
```

## Implementation Plan

### Phase 1: Core Infrastructure

#### 1.1 Create DocRefIdResolver Interface

```dart
// packages/tercen_json_path/lib/src/doc_ref_id_resolver.dart

/// Resolves in-document references by searching the document tree.
abstract class DocRefIdResolver {
  /// Check if this resolver handles the given kind
  bool handlesKind(String kind);

  /// Resolve a reference within the document.
  ///
  /// [refId] - The ID to search for
  /// [targetKind] - The expected kind of the target object
  /// [rootDocument] - The root document to search within
  /// [searchPath] - Optional path hint for optimization
  ///
  /// Returns the resolved object or null if not found.
  Future<Map<String, dynamic>?> resolveInDocument(
    String refId,
    String targetKind,
    Map<String, dynamic> rootDocument, {
    String? searchPath,
  });
}
```

#### 1.2 Default Implementation

```dart
// packages/tercen_json_path/lib/src/default_doc_ref_id_resolver.dart

class DefaultDocRefIdResolver implements DocRefIdResolver {
  /// Cache for resolved references within a query execution
  final Map<String, Map<String, dynamic>?> _cache = {};

  /// Index of objects by id for fast lookup
  Map<String, Map<String, dynamic>>? _idIndex;

  @override
  bool handlesKind(String kind) => true; // Handle all kinds by default

  @override
  Future<Map<String, dynamic>?> resolveInDocument(
    String refId,
    String targetKind,
    Map<String, dynamic> rootDocument, {
    String? searchPath,
  }) async {
    final cacheKey = '$refId:$targetKind';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Build index on first access
    _idIndex ??= _buildIdIndex(rootDocument);

    // Look up by ID
    final candidate = _idIndex![refId];
    if (candidate != null && candidate['kind'] == targetKind) {
      _cache[cacheKey] = candidate;
      return candidate;
    }

    _cache[cacheKey] = null;
    return null;
  }

  /// Build an index of all objects by their 'id' field
  Map<String, Map<String, dynamic>> _buildIdIndex(dynamic json) {
    final index = <String, Map<String, dynamic>>{};
    _indexRecursively(json, index);
    return index;
  }

  void _indexRecursively(dynamic json, Map<String, Map<String, dynamic>> index) {
    if (json is Map<String, dynamic>) {
      final id = json['id'] as String?;
      if (id != null && id.isNotEmpty) {
        index[id] = json;
      }
      for (final value in json.values) {
        _indexRecursively(value, index);
      }
    } else if (json is List) {
      for (final item in json) {
        _indexRecursively(item, index);
      }
    }
  }

  /// Clear cache between query executions
  void clearCache() {
    _cache.clear();
    _idIndex = null;
  }
}
```

### Phase 2: Parser Integration

#### 2.1 Add Grammar for `@@` Syntax

```dart
// packages/tercen_json_path/lib/src/grammar/doc_dereference.dart

Parser<Selector> docDereferenceParser(DocRefIdResolver? resolver) {
  final nameChar = letter() | digit() | char('_');
  final name = (letter() | char('_')) & nameChar.star();

  // Pattern: fieldName@@TargetKind
  return (name.flatten() & string('@@') & name.flatten()).map((parts) {
    final fieldName = parts[0] as String;
    final targetKind = parts[2] as String;
    return docDereferenceSelector(fieldName, targetKind, resolver);
  });
}
```

#### 2.2 Create Selector Implementation

```dart
// packages/tercen_json_path/lib/src/grammar/doc_dereference_selector.dart

Selector docDereferenceSelector(
  String fieldName,
  String targetKind,
  DocRefIdResolver? resolver,
) {
  return (NodeStream nodes) {
    return MultiNodeStream((() async* {
      if (resolver == null) return;

      await for (final node in nodes) {
        if (node.value is! Map) continue;

        final map = node.value as Map;
        final refIdValue = map[fieldName];

        if (refIdValue == null || refIdValue is! String) continue;
        if (refIdValue.isEmpty) continue;

        // Get root document from node
        final rootValue = node.root.value;
        if (rootValue is! Map<String, dynamic>) continue;

        try {
          final targetObject = await resolver.resolveInDocument(
            refIdValue,
            targetKind,
            rootValue,
          );

          if (targetObject != null) {
            yield Node(targetObject);
          }
        } catch (e) {
          continue;
        }
      }
    })());
  };
}
```

#### 2.3 Integrate into Grammar

```dart
// packages/tercen_json_path/lib/src/grammar/json_path.dart

Parser<Selector> _segment() => [
  // Try @@ (doc dereference) first
  docDereferenceParser(_docRefIdResolver).skip(before: char('.')),
  // Then @ (external dereference)
  dereferenceParser(_resolver).skip(before: char('.')),
  // Then regular property access
  dotName,
  wildcard.skip(before: char('.')),
  ref0(_union),
  ref0(_recursion),
].toChoiceParser().trim();
```

### Phase 3: API Updates

#### 3.1 Update JsonPath Factory

```dart
factory JsonPath(
  String expression, {
  RefIdResolver? resolver,
  VirtualPropertyResolver? virtualPropertyResolver,
  DocRefIdResolver? docRefIdResolver,  // NEW
}) => JsonPathParser().parse(
  expression,
  resolver: resolver,
  virtualPropertyResolver: virtualPropertyResolver,
  docRefIdResolver: docRefIdResolver,
);
```

### Phase 4: Code Generation (Optional)

Generate `DOC_REF_IDS` metadata in model base classes similar to `REF_IDS`:

```dart
// Generated in sci_api_model/lib/src/model/base/step.dart
class StepBase extends IdObject {
  static const List<base.DocRefId> DOC_REF_IDS = [
    base.DocRefId("GroupStep", Vocabulary.groupId_DP, searchPath: r'$.steps[*]'),
  ];
  // ...
}
```

## Syntax Comparison

| Use Case | Current | With DocRefId |
|----------|---------|---------------|
| Get group name for a step | Manual Dart code | `$.steps[0].groupId@@GroupStep.name` |
| Get input port for a link | `link.input` getter | `$.links[0].inputId@@InputPort` |
| Filter by group property | N/A | `$.steps[?@.groupId@@GroupStep.appName == 'PCA']` |

## Edge Cases to Handle

1. **Null/Empty References**: Skip gracefully when `groupId` is null or empty
2. **Missing Targets**: Return null when referenced object doesn't exist
3. **Kind Mismatch**: Validate that found object has expected kind
4. **Circular References**: Not applicable (IDs are strings, not nested objects)
5. **Performance**: Build ID index lazily, cache within query execution

## Testing Strategy

```dart
group('DocRefId @@ dereferencing', () {
  test('resolves groupId to GroupStep', () async {
    final workflow = {
      'steps': [
        {'kind': 'DataStep', 'id': 's1', 'groupId': 'g1'},
        {'kind': 'GroupStep', 'id': 'g1', 'name': 'Analysis'},
      ],
    };

    final path = JsonPath(
      r"$.steps[?@.id == 's1'].groupId@@GroupStep.name",
      docRefIdResolver: DefaultDocRefIdResolver(),
    );
    final results = await path.readValues(workflow).toList();

    expect(results, ['Analysis']);
  });

  test('resolves link inputId to InputPort', () async {
    final workflow = {
      'steps': [
        {'kind': 'DataStep', 'id': 's1', 'inputs': [
          {'kind': 'InputPort', 'id': 'p1', 'name': 'table'}
        ]},
      ],
      'links': [
        {'kind': 'Link', 'inputId': 'p1', 'outputId': 'p2'},
      ],
    };

    final path = JsonPath(
      r"$.links[0].inputId@@InputPort.name",
      docRefIdResolver: DefaultDocRefIdResolver(),
    );
    final results = await path.readValues(workflow).toList();

    expect(results, ['table']);
  });
});
```

## Future Enhancements

### Parent Access Syntax

To get the parent object of a resolved reference (e.g., the Step containing an InputPort), consider adding a `$parent` virtual property:

```jsonpath
# Get the step that owns the input port
$.links[0].inputId@@InputPort.$parent.$parent  # InputPort -> inputs array -> Step
```

Or a dedicated syntax:

```jsonpath
# Hypothetical: Get parent of kind
$.links[0].inputId@@InputPort.$parentOf(Step)
```

### Bidirectional Resolution

Support reverse lookups - finding objects that reference a given ID:

```jsonpath
# Find all links pointing to a specific port
$.links[?@.inputId == 'port1']  # Already possible

# Hypothetical: Find referencing objects
$['port1']@@<Link.inputId  # Objects of kind Link where inputId == 'port1'
```

## Files to Create/Modify

### New Files
- `packages/tercen_json_path/lib/src/doc_ref_id_resolver.dart`
- `packages/tercen_json_path/lib/src/default_doc_ref_id_resolver.dart`
- `packages/tercen_json_path/lib/src/grammar/doc_dereference.dart`
- `packages/tercen_json_path/lib/src/grammar/doc_dereference_selector.dart`
- `packages/tercen_json_path/test/doc_ref_id_test.dart`
- `sci_api_gen/lib/src/doc_ref_id.dart` (annotation)

### Modified Files
- `packages/tercen_json_path/lib/src/grammar/json_path.dart` (grammar integration)
- `packages/tercen_json_path/lib/src/json_path.dart` (factory update)
- `packages/tercen_json_path/lib/src/json_path_parser.dart` (parameter)
- `packages/tercen_json_path/lib/src/json_path_internal.dart` (pass resolver)
- `packages/tercen_json_path/lib/src/node.dart` (optional: carry resolver)
- `packages/tercen_json_path/lib/json_path.dart` (exports)

## Summary

The `DocRefId` annotation and `@@` syntax provide a clean way to dereference in-document references in JSONPath queries, complementing the existing `@` syntax for external references and virtual properties for computed relationships.

| Feature | Syntax | Use Case |
|---------|--------|----------|
| External Reference | `@` | Cross-document (database) |
| Document Reference | `@@` | Same-document (by ID) |
| Virtual Property | property name | Computed/derived |
