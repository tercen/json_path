/// Inspectable AST representation of a JSONPath expression.
///
/// Unlike the execution grammar which compiles to opaque closures,
/// AST nodes retain structural information (field names, collection names,
/// filter references, dereference targets) for static analysis.
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// The parsed AST of a JSONPath expression.
class JsonPathAst {
  final String expression;
  final List<JsonPathSegment> segments;

  JsonPathAst(this.expression, this.segments);

  @override
  String toString() => 'JsonPathAst($expression, ${segments.length} segments)';
}

/// Base class for all JSONPath segments.
sealed class JsonPathSegment {
  /// Character offset in source expression for error reporting.
  final int position;

  JsonPathSegment(this.position);
}

/// Property access: `.name`, `.description`
class DotNameSegment extends JsonPathSegment {
  final String name;

  DotNameSegment(this.name, super.position);

  @override
  String toString() => 'DotName($name)';
}

/// Wildcard: `[*]` or `.*`
class WildcardSegment extends JsonPathSegment {
  WildcardSegment(super.position);

  @override
  String toString() => 'Wildcard';
}

/// Array index: `[0]`, `[3]`
class ArrayIndexSegment extends JsonPathSegment {
  final int index;

  ArrayIndexSegment(this.index, super.position);

  @override
  String toString() => 'ArrayIndex($index)';
}

/// Array slice: `[0:5]`, `[::2]`
class ArraySliceSegment extends JsonPathSegment {
  final int? start;
  final int? end;
  final int? step;

  ArraySliceSegment({this.start, this.end, this.step, required int position})
      : super(position);

  @override
  String toString() => 'ArraySlice($start:$end:$step)';
}

/// Filter: `[?@.name == 'Test']`, `[?@.id == 'xxx' || @.id == 'yyy']`
class FilterSegment extends JsonPathSegment {
  /// Fields referenced in the filter expression.
  final List<FilterFieldRef> fieldRefs;

  /// Logical operator combining multiple conditions.
  final FilterLogicalOperator operator;

  FilterSegment(this.fieldRefs, this.operator, super.position);

  @override
  String toString() =>
      'Filter(${fieldRefs.map((r) => r.toString()).join(' ${operator.name} ')})';
}

/// A field reference within a filter expression.
class FilterFieldRef {
  /// The property name, e.g., "name", "id".
  final String property;

  /// The comparison operator, e.g., "==", "!=", ">", "<".
  final String compOperator;

  /// The literal value being compared (null for non-literal comparisons).
  final String? value;

  FilterFieldRef(this.property, this.compOperator, [this.value]);

  @override
  String toString() => '$property $compOperator ${value ?? '?'}';
}

// FilterLogicalOperator is imported from virtual_hierarchy_plan.dart

/// Union selector: `['name', 'kind']`, `[0, 2]`
class UnionSegment extends JsonPathSegment {
  final List<UnionElement> elements;

  UnionSegment(this.elements, super.position);

  @override
  String toString() =>
      'Union(${elements.map((e) => e.toString()).join(', ')})';
}

/// Base class for union elements.
sealed class UnionElement {}

/// A named field in a union: `'name'`
class FieldNameElement extends UnionElement {
  final String name;

  FieldNameElement(this.name);

  @override
  String toString() => "'$name'";
}

/// A numeric index in a union: `0`, `2`
class IndexElement extends UnionElement {
  final int index;

  IndexElement(this.index);

  @override
  String toString() => '$index';
}

/// RefId dereference: `.projectId@Project`
class DereferenceSegment extends JsonPathSegment {
  final String fieldName;
  final String targetKind;

  DereferenceSegment(this.fieldName, this.targetKind, super.position);

  @override
  String toString() => 'Deref($fieldName@$targetKind)';
}

/// Recursive descent: `..name`, `..[*]`
class RecursionSegment extends JsonPathSegment {
  final JsonPathSegment inner;

  RecursionSegment(this.inner, super.position);

  @override
  String toString() => 'Recursion($inner)';
}

/// Object projection: `{name, kind, acl.owner}`
class ProjectionSegment extends JsonPathSegment {
  final List<String> fieldPaths;

  ProjectionSegment(this.fieldPaths, super.position);

  @override
  String toString() => 'Projection(${fieldPaths.join(', ')})';
}
