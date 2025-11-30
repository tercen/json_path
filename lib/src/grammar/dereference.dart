import 'package:petitparser/petitparser.dart';
import 'package:tercen_json_path/src/grammar/dereference_selector.dart';
import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:tercen_json_path/src/selector.dart';

/// Parser for @ dereferencing syntax: fieldName@TargetKind
///
/// Examples:
/// - operatorId@Operator
/// - projectId@Project
/// - userId@User
///
/// Grammar:
/// ```
/// dereference = name-char+ "@" name-char+
/// ```
///
/// The parser produces a Selector that dereferences the field.
/// Note: The resolver must be injected at parse time via the JsonPathParser.
Parser<Selector> dereferenceParser(RefIdResolver? resolver) {
  // Name pattern: letter/underscore followed by letter/digit/underscore
  final nameChar = letter() | digit() | char('_');
  final name = (letter() | char('_')) & nameChar.star();

  return (name.flatten() & char('@') & name.flatten()).map((parts) {
    final fieldName = parts[0] as String;
    final targetKind = parts[2] as String;
    return dereferenceSelector(fieldName, targetKind, resolver);
  });
}
