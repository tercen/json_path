import 'package:tercen_json_path/src/expression/expression.dart';
import 'package:tercen_json_path/src/expression/nodes.dart';
import 'package:tercen_json_path/src/fun/fun.dart';
import 'package:tercen_json_path/src/fun/fun_factory.dart';
import 'package:tercen_json_path/src/fun/standard/count.dart';
import 'package:tercen_json_path/src/fun/standard/length.dart';
import 'package:tercen_json_path/src/fun/standard/match.dart';
import 'package:tercen_json_path/src/fun/standard/search.dart';
import 'package:tercen_json_path/src/fun/standard/value.dart';
import 'package:tercen_json_path/src/grammar/json_path.dart';
import 'package:tercen_json_path/src/json_path.dart';
import 'package:tercen_json_path/src/json_path_internal.dart';
import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:tercen_json_path/src/selector.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_analyzer.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';
import 'package:tercen_json_path/src/virtual_property_resolver.dart';
import 'package:petitparser/petitparser.dart';

/// A customizable JSONPath parser.
class JsonPathParser {
  /// Creates an instance of the parser.
  factory JsonPathParser({Iterable<Fun> functions = const []}) =>
      functions.isEmpty ? _standard : JsonPathParser._(functions);

  JsonPathParser._(Iterable<Fun> functions)
      : _parser = JsonPathGrammarDefinition(
          FunFactory(_stdFun.followedBy(functions)),
        ).build(),
        _analyzer = VirtualHierarchyAnalyzer();

  /// The standard instance is pre-cached to speed up parsing when only
  /// the standard built-in functions are used.
  static final _standard = JsonPathParser._(_stdFun);

  /// Standard functions
  static const _stdFun = <Fun>[Count(), Length(), Match(), Search(), Value()];

  final Parser<Expression<NodeList>> _parser;
  final VirtualHierarchyAnalyzer _analyzer;

  /// Parses the JSONPath from s string [expression].
  /// Returns an instance of [JsonPath] or throws a [FormatException].
  ///
  /// Optional [resolver] enables @ dereferencing syntax.
  /// Optional [virtualPropertyResolver] enables computed properties like
  /// `parentSteps`, `childSteps`, etc.
  JsonPath parse(
    String expression, {
    RefIdResolver? resolver,
    VirtualPropertyResolver? virtualPropertyResolver,
  }) {
    // If resolver is provided, build a custom parser with it
    // Otherwise use the cached parser
    final parser = resolver != null
        ? JsonPathGrammarDefinition(
            FunFactory(_stdFun.followedBy(const [])),
            resolver,
          ).build()
        : _parser;

    final expr = parser.parse(expression).value;
    // Adapt Expression<NodeList> (which expects Node) to Selector (which expects NodeStream)
    final Selector selector = (NodeStream nodes) {
      return MultiNodeStream((() async* {
        await for (final node in nodes) {
          final result = await expr.call(node);
          yield* result;
        }
      })());
    };

    // Analyze hierarchy requirements if we have a virtual resolver
    VirtualHierarchyPlan? plan;
    VirtualHierarchyResolver? virtualResolver;

    if (resolver is VirtualHierarchyResolver) {
      plan = _analyzer.analyze(expression);
      virtualResolver = resolver;
    }

    return JsonPathInternal(
      expression,
      selector,
      resolver: virtualResolver,
      hierarchyPlan: plan,
      virtualPropertyResolver: virtualPropertyResolver,
    );
  }
}
