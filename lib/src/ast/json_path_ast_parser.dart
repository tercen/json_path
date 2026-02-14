import 'package:petitparser/petitparser.dart';
import 'package:tercen_json_path/src/ast/json_path_ast.dart';
import 'package:tercen_json_path/src/ast/json_path_ast_grammar.dart';

/// Parses JSONPath expressions into inspectable [JsonPathAst] trees.
///
/// Unlike [JsonPathParser] which compiles to executable closures,
/// this parser produces a structural AST suitable for static analysis
/// and validation.
class JsonPathAstParser {
  static final _instance = JsonPathAstParser._();
  static final _parser = JsonPathAstGrammarDefinition().build();

  JsonPathAstParser._();

  factory JsonPathAstParser() => _instance;

  /// Parses [expression] into a [JsonPathAst].
  ///
  /// Throws [FormatException] if the expression is not valid JSONPath syntax.
  JsonPathAst parse(String expression) {
    final result = _parser.parse(expression);
    if (result is Failure) {
      throw FormatException(
        'Invalid JSONPath: ${result.message}',
        expression,
        result.position,
      );
    }
    return JsonPathAst(expression, result.value);
  }
}
