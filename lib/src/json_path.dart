import 'package:tercen_json_path/src/json_path_match.dart';
import 'package:tercen_json_path/src/json_path_parser.dart';

/// A parsed JSONPath expression which can be applied to a JSON document.
abstract interface class JsonPath {
  /// Creates an instance from a string. The [expression] is parsed once, and
  /// the instance may be used many times after that.
  ///
  /// Throws [FormatException] if the [expression] can not be parsed.
  factory JsonPath(String expression) => JsonPathParser().parse(expression);

  /// Reads the given [json] object returning a Stream of all matches found.
  Stream<JsonPathMatch> read(dynamic json);

  /// Reads the given [json] object returning a Stream of all values found.
  Stream<Object?> readValues(dynamic json);
}
