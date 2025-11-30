/// A named function which can be used in a JSONPath expression.
abstract interface class Fun {
  /// Function name.
  String get name;
}

/// A named function with one argument.
/// The return type [R] and the argument type [T] must be one of the following:
/// - [bool]
/// - [Maybe]
/// - [NodeList]
/// The call method may return R or Future<R> for async support.
abstract interface class Fun1<R extends Object, T extends Object> extends Fun {
  /// Applies the given arguments.
  /// This method MUST throw an [Exception] on invalid args.
  /// May return R or Future<R> for async operations.
  dynamic call(T arg);
}

/// A named function with two arguments.
/// The return type [R] and the argument types [T1], [T2] must be one of the following:
/// - [bool]
/// - [Maybe]
/// - [NodeList]
/// The call method may return R or Future<R> for async support.
abstract interface class Fun2<
  R extends Object,
  T1 extends Object,
  T2 extends Object
>
    extends Fun {
  /// Applies the given arguments.
  /// This method MUST throw an [Exception] on invalid args.
  /// May return R or Future<R> for async operations.
  dynamic call(T1 first, T2 second);
}
