import 'package:tercen_json_path/src/json_path_match.dart';
import 'package:tercen_json_path/src/json_path_parser.dart';
import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:tercen_json_path/src/virtual_property_resolver.dart';

/// A parsed JSONPath expression which can be applied to a JSON document.
abstract interface class JsonPath {
  /// Creates an instance from a string. The [expression] is parsed once, and
  /// the instance may be used many times after that.
  ///
  /// Throws [FormatException] if the [expression] can not be parsed.
  ///
  /// Optional [resolver] parameter enables @ dereferencing syntax.
  /// If not provided, @ expressions will be parsed but dereferencing will be skipped.
  ///
  /// Optional [virtualPropertyResolver] parameter enables computed properties
  /// like `parentSteps`, `childSteps`, `ancestorSteps`, `descendantSteps` for
  /// navigating step relationships within Workflow documents.
  factory JsonPath(
    String expression, {
    RefIdResolver? resolver,
    VirtualPropertyResolver? virtualPropertyResolver,
  }) =>
      JsonPathParser().parse(
        expression,
        resolver: resolver,
        virtualPropertyResolver: virtualPropertyResolver,
      );

  /// Reads the given [json] object returning a Stream of all matches found.
  Stream<JsonPathMatch> read(dynamic json);

  /// Reads the given [json] object returning a Stream of all values found.
  Stream<Object?> readValues(dynamic json);
}
