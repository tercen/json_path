import 'package:tercen_json_path/src/expression/expression.dart';

/// A special case of [Expression] where the value is known at parse time.
class StaticExpression<T extends Object> extends Expression<T> {
  StaticExpression(this.value) : super((_) => Future.value(value));

  final T value;

  @override
  Expression<R> map<R extends Object>(Future<R> Function(T v) mapper) =>
      Expression((_) => mapper(value));

  @override
  Expression<R> mapSync<R extends Object>(R Function(T v) mapper) =>
      StaticExpression(mapper(value));

  @override
  Expression<R> merge<R extends Object, M extends Object>(
    Expression<M> other,
    Future<R> Function(T v, M m) merger,
  ) => other is StaticExpression<M>
      ? Expression((_) => merger(value, other.value))
      : super.merge(other, merger);
}
