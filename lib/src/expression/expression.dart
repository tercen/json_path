import 'package:tercen_json_path/src/node.dart';

/// An expression applicable to a JSON node. For example:
/// `length(@.foo) > 3 && @.bar`. The `@` denotes the current node
/// being processed by JSONPath.
///
/// Expressions are now async to support stream operations and @ dereferencing.
class Expression<T extends Object> {
  Expression(this.call);

  /// Returns the result of applying the expression to the node.
  /// This is now async to support stream-based evaluation.
  final Future<T> Function(Node) call;

  /// Creates a new [Expression] by applying the [mapper] function
  /// to the result of this expression.
  Expression<R> map<R extends Object>(Future<R> Function(T v) mapper) =>
      Expression((node) async => await mapper(await call(node)));

  /// Creates a new [Expression] by applying a sync [mapper] function.
  Expression<R> mapSync<R extends Object>(R Function(T v) mapper) =>
      Expression((node) async => mapper(await call(node)));

  /// Creates a new [Expression] from the [other] [Expression] and the
  /// [merger] function. The [merger] function is applied to the values
  /// produced by this an the [other] [Expression].
  Expression<R> merge<R extends Object, M extends Object>(
    Expression<M> other,
    Future<R> Function(T a, M b) merger,
  ) => Expression(
        (node) async => await merger(await call(node), await other.call(node)),
      );
}
