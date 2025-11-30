import 'package:tercen_json_path/src/expression/expression.dart';
import 'package:tercen_json_path/src/grammar/array_index.dart';
import 'package:tercen_json_path/src/grammar/child_selector.dart';
import 'package:tercen_json_path/src/grammar/dot_name.dart';
import 'package:tercen_json_path/src/grammar/parser_ext.dart';
import 'package:tercen_json_path/src/grammar/sequence_selector.dart';
import 'package:tercen_json_path/src/grammar/strings.dart';
import 'package:tercen_json_path/src/selector.dart';
import 'package:petitparser/petitparser.dart';

final _singularUnionElement = [
  arrayIndex,
  quotedString.map(childSelector),
].toChoiceParser().trim();

final _singularUnion = _singularUnionElement.inBrackets();

final _singularSegment = [dotName, _singularUnion].toChoiceParser().trim();

final singularSegmentSequence = _singularSegment
    .star()
    .map((List<dynamic> segments) {
      // Segments are Selectors, but singularSequenceSelector expects SingularSelectors
      // We can use sequenceSelector instead which accepts Selectors
      return sequenceSelector(segments.cast<Selector>());
    })
    .map((fn) => Expression((node) => Future.value(fn(node))));
