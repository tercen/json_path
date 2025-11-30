# Parse-Time Singularity Validation - Design Analysis

## Question: Would Async Parsing Enable Parse-Time Validation?

**Short Answer**: No - async parsing doesn't solve the type system issue.

**Long Answer**: The parser already distinguishes singular vs plural queries, but the type system loses this information.

## Current Parser Architecture

### Parser Already Knows! ✅

```dart
// Grammar has SEPARATE parsers for singular vs plural:
Parser<Expression<NodeList>> _singularFilterPath() { ... }  // @ alone
Parser<Expression<NodeList>> _filterPath() { ... }          // @.*, etc.
```

The parser uses `_singularFilterPath()` for expressions like `@` and `_filterPath()` for `@.*`.

**The problem**: Both return `Expression<NodeList>` where `NodeList = NodeStream`, losing the singularity information!

### Type Information Is Lost

```dart
// Parser knows this is singular:
_singularFilterPath() → Expression<NodeList>

// Parser knows this is plural:
_filterPath() → Expression<NodeList>

// But both have the SAME TYPE!
// Singularity information is erased ❌
```

## What Async Parsing Would Give Us

### Async Parsing Capabilities

```dart
Future<JsonPath> parseAsync(String expression) async {
  // We could do async operations during parsing:

  // 1. Async validation
  await validateSyntax(expression);

  // 2. Async optimization
  final optimized = await optimizeQuery(expression);

  // 3. Async schema validation (if schema provided)
  await validateAgainstSchema(expression, schema);
}
```

### What Async CANNOT Do

❌ Change the type system
❌ Make `Expression<NodeList>` distinguish singular vs plural
❌ Enable compile-time type checking without Expression-level types

## The Real Solution: Expression-Level Singularity Types

### Option 1: Parameterized Expression Types

```dart
// Change Expression to be parameterized by stream type
class Expression<T extends NodeStream> {
  final Future<T> Function(Node) call;

  Expression(this.call);
}

// Then:
Expression<SingularNodeStream>  // Singular queries
Expression<MultiNodeStream>     // Plural queries

// And functions:
class Key implements Fun1<Maybe, Expression<SingularNodeStream>> {
  Future<Maybe> call(Expression<SingularNodeStream> expr) { ... }
}
```

### Option 2: Wrapper Types

```dart
// Create wrapper types:
class SingularExpression {
  final Expression<NodeList> _expr;
  SingularExpression(this._expr);

  Future<SingularNodeStream> call(Node node) async {
    final result = await _expr.call(node);
    return result.toSingular();  // Runtime validation
  }
}

class MultiExpression {
  final Expression<NodeList> _expr;
  MultiExpression(this._expr);

  Future<MultiNodeStream> call(Node node) async {
    final result = await _expr.call(node);
    if (result is MultiNodeStream) return result;
    if (result is SingularNodeStream) {
      return MultiNodeStream.fromIterable([result.node]);
    }
    return result as MultiNodeStream;
  }
}

// Parser returns specific types:
Parser<SingularExpression> _singularFilterPath() { ... }
Parser<MultiExpression> _filterPath() { ... }

// Functions require specific types:
class Key implements Fun1<Maybe, SingularExpression> {
  Future<Maybe> call(SingularExpression expr) { ... }
}
```

### Option 3: Hybrid - Parse-Time Validation, Runtime Enforcement

```dart
// Keep current Expression<NodeList> architecture
// But add parse-time validation metadata:

class Expression<T> {
  final Future<T> Function(Node) call;
  final QuerySingularity singularity;  // NEW

  Expression(this.call, {this.singularity = QuerySingularity.unknown});
}

enum QuerySingularity {
  singular,   // Guaranteed 1 node
  plural,     // 0 or more nodes
  unknown,    // Data-dependent
}

// Parser sets singularity:
Parser<Expression<NodeList>> _singularFilterPath() =>
  ... .map((fn) => Expression(fn, singularity: QuerySingularity.singular));

// FunFactory validates:
Expression<T> _any1<T>(String name, Expression a0) {
  final f = _getFun1<T>(name);

  if (f is Fun1<T, SingularNodeStream> &&
      a0.singularity == QuerySingularity.plural) {
    throw FormatException(
      '$name() requires singular query, got plural: ${a0}'
    );
  }

  // ... rest of logic
}
```

## Complexity Analysis

| Solution | Complexity | Type Safety | Parse-Time Validation | Breaking Changes |
|----------|-----------|-------------|---------------------|------------------|
| **Current** | Low | Runtime | ❌ | None |
| **Option 1** | High | Compile-time | ❌ | Major |
| **Option 2** | Medium | Compile-time | ❌ | Major |
| **Option 3** | Low | Runtime | ✅ | Minor |

## Recommendation: Option 3 - Hybrid Approach

### Why Option 3 is Optimal

1. **Low complexity** - Add metadata field, validation in FunFactory
2. **Parse-time validation** - Catches errors during parse
3. **Minimal breaking changes** - Expression signature stays same
4. **Clear errors** - "key() requires singular query, got plural: @.*"
5. **No type system overhaul** - Works with current architecture

### Implementation Plan

```dart
// Step 1: Add singularity enum
enum QuerySingularity { singular, plural, unknown }

// Step 2: Add field to Expression
class Expression<T> {
  final Future<T> Function(Node) call;
  final QuerySingularity singularity;  // NEW

  Expression(this.call, {this.singularity = QuerySingularity.unknown});
}

// Step 3: Update grammar parsers
Parser<Expression<NodeList>> _singularFilterPath() =>
  ... .map((fn) => Expression(
    fn,
    singularity: QuerySingularity.singular
  ));

Parser<Expression<NodeList>> _filterPath() =>
  ... .map((fn) => Expression(
    fn,
    singularity: QuerySingularity.plural  // If has .*, [*], etc.
  ));

// Step 4: Add validation to FunFactory
Expression<T> _any1<T>(String name, Expression a0) {
  final f = _getFun1<T>(name);

  // NEW: Validate singularity
  if (f is Fun1<T, SingularNodeStream>) {
    if (a0.singularity == QuerySingularity.plural) {
      throw FormatException(
        '$name() requires a singular query expression, '
        'but was given: ${_describeQuery(a0)}'
      );
    }
  }

  // ... existing logic
}

// Step 5: Helper for error messages
String _describeQuery(Expression expr) {
  // Could store original query string in Expression
  // For now, use singularity info
  switch (expr.singularity) {
    case QuerySingularity.plural:
      return 'a plural query (e.g., @.*, $[*])';
    case QuerySingularity.singular:
      return 'a singular query (@)';
    case QuerySingularity.unknown:
      return 'a query with unknown cardinality';
  }
}
```

### Benefits

✅ **Parse-time validation** - Errors thrown during parse()
✅ **Clear error messages** - "key() requires singular query"
✅ **Minimal complexity** - One enum, one field, validation logic
✅ **No breaking changes** - Expression API stays compatible
✅ **Un-skips 2 tests** - key(@.*) and index(@.*) will throw FormatException

### Effort Estimate

- **Implementation**: 2-3 hours
- **Testing**: 1 hour
- **Total**: Half day

## Conclusion

**Async parsing**: Not the solution - doesn't solve type system issue.

**Real solution**: Option 3 (Hybrid) - Add QuerySingularity metadata to Expression and validate in FunFactory.

This gives us **parse-time validation** with **minimal complexity** and **no breaking changes**!

## Next Steps

If we want to un-skip the 2 tests:
1. Implement Option 3 (Hybrid approach)
2. Add QuerySingularity enum
3. Update Expression class
4. Update grammar parsers
5. Add validation in FunFactory
6. Un-skip key(@.*) and index(@.*) tests
7. Tests will pass! ✅

**Estimated effort**: Half day
**Risk**: Low
**Benefit**: Un-skip 2 tests, clearer errors for users
