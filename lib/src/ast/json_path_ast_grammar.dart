/// PetitParser grammar that produces [JsonPathAst] nodes.
///
/// Mirrors the structure of [JsonPathGrammarDefinition] but maps parser output
/// to inspectable AST nodes instead of opaque Selectors/Expressions.
import 'package:petitparser/petitparser.dart';
import 'package:tercen_json_path/src/ast/json_path_ast.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';
import 'package:tercen_json_path/src/grammar/number.dart';
import 'package:tercen_json_path/src/grammar/parser_ext.dart';
import 'package:tercen_json_path/src/grammar/strings.dart';

class JsonPathAstGrammarDefinition
    extends GrammarDefinition<List<JsonPathSegment>> {
  @override
  Parser<List<JsonPathSegment>> start() =>
      _segments().skip(before: char(r'$')).end();

  Parser<List<JsonPathSegment>> _segments() => _segment().star();

  Parser<JsonPathSegment> _segment() => [
        _dereference(),
        _dotName(),
        _wildcardDot(),
        _projection(),
        _recursion(),
        _bracketContent(),
      ].toChoiceParser().trim();

  // -- Dot segments --

  /// `.fieldName@TargetKind`
  Parser<DereferenceSegment> _dereference() {
    final nameChar = letter() | digit() | char('_');
    final name = (letter() | char('_')) & nameChar.star();

    return (name.flatten() & char('@') & name.flatten())
        .skip(before: char('.'))
        .map2((v, pos) {
      final fieldName = v[0] as String;
      final targetKind = v[2] as String;
      return DereferenceSegment(fieldName, targetKind, pos);
    });
  }

  /// `.fieldName`
  Parser<DotNameSegment> _dotName() => _memberName()
      .skip(before: char('.'))
      .map2((name, pos) => DotNameSegment(name, pos));

  /// `.*`
  Parser<WildcardSegment> _wildcardDot() =>
      char('*').skip(before: char('.')).map2((_, pos) => WildcardSegment(pos));

  /// `{name, kind, acl.owner}`
  Parser<ProjectionSegment> _projection() {
    final fieldPath =
        _memberName().toList(char('.').trim()).map((parts) => parts.join('.'));
    return fieldPath
        .toList()
        .skip(before: char('{'), after: char('}'))
        .map2((paths, pos) => ProjectionSegment(paths, pos));
  }

  /// `..inner`
  Parser<RecursionSegment> _recursion() => [
        char('*').map2((_, pos) => WildcardSegment(pos)),
        _bracketContent(),
        _memberName().map2((name, pos) => DotNameSegment(name, pos)),
      ].toChoiceParser().skip(before: string('..')).map2((inner, pos) {
        return RecursionSegment(inner, pos);
      });

  // -- Bracket segments --

  /// `[contents]` — dispatches to filter, wildcard, slice, index, union
  Parser<JsonPathSegment> _bracketContent() =>
      _bracketInner().inBrackets();

  Parser<JsonPathSegment> _bracketInner() => [
        _expressionFilter(),
        _wildcardBracket(),
        _sliceOrIndexOrUnion(),
      ].toChoiceParser().trim();

  /// `[*]`
  Parser<WildcardSegment> _wildcardBracket() =>
      char('*').trim().map2((_, pos) => WildcardSegment(pos));

  /// `[?expression]`
  Parser<FilterSegment> _expressionFilter() =>
      _logicalExpr().skip(before: char('?').trim()).map2((refs, pos) {
        final allRefs = refs.expand((e) => e.fieldRefs).toList();
        final op = refs.length > 1
            ? FilterLogicalOperator.or
            : (refs.length == 1 && refs.first.fieldRefs.length > 1 &&
                       refs.first.operator == FilterLogicalOperator.and
                   ? FilterLogicalOperator.and
                   : refs.length == 1
                       ? refs.first.operator
                       : FilterLogicalOperator.single);
        return FilterSegment(allRefs, op, pos);
      });

  /// Logical OR sequence: `expr || expr || ...`
  Parser<List<_FilterGroup>> _logicalExpr() =>
      _logicalAndExpr().toList(string('||'));

  /// Logical AND sequence: `expr && expr && ...`
  Parser<_FilterGroup> _logicalAndExpr() =>
      _basicExpr().toList(string('&&')).map((refs) {
        return _FilterGroup(refs, refs.length > 1
            ? FilterLogicalOperator.and
            : FilterLogicalOperator.single);
      });

  /// Basic expression: comparison, existence test, parenthesized, or function
  Parser<FilterFieldRef> _basicExpr() => [
        _parenExpr(),
        _comparisonExpr(),
        _existenceTest(),
      ].toChoiceParser();

  /// `(logicalExpr)` — optionally negated
  Parser<FilterFieldRef> _parenExpr() => _comparisonExpr()
      .inParens()
      .skip(before: char('!').trim().optional());

  /// `@.property op value` or `value op @.property`
  Parser<FilterFieldRef> _comparisonExpr() {
    final cmpOp = ['==', '!=', '<=', '>=', '<', '>']
        .map(string)
        .toChoiceParser()
        .trim();

    return (_comparable() & cmpOp & _comparable()).map((v) {
      final left = v[0] as _Comparable;
      final op = v[1] as String;
      final right = v[2] as _Comparable;

      // Extract field ref from whichever side has the path
      if (left.isPath) {
        return FilterFieldRef(left.value, op, right.isPath ? null : right.value);
      } else if (right.isPath) {
        // Reverse the operator for right-side path
        return FilterFieldRef(right.value, _reverseOp(op), left.value);
      }
      // Both literals — unusual but valid; use left as property
      return FilterFieldRef(left.value, op, right.value);
    });
  }

  /// Existence test: `@.property` (optionally negated)
  Parser<FilterFieldRef> _existenceTest() {
    final negated = _filterRelPath()
        .skip(before: char('!').trim())
        .map((prop) => FilterFieldRef(prop, '!exists'));

    return [negated, _filterRelPath().map((prop) => FilterFieldRef(prop, 'exists'))].toChoiceParser();
  }

  /// Value in a comparison: literal or filter path
  Parser<_Comparable> _comparable() => [
        _filterRelPath().map((prop) => _Comparable(prop, isPath: true)),
        _literal().map((val) => _Comparable(val, isPath: false)),
      ].toChoiceParser().trim();

  /// `@.property` — relative filter path, returns the property name
  Parser<String> _filterRelPath() {
    final nameChar = letter() | digit() | char('_');
    final name = ((letter() | char('_')) & nameChar.star()).flatten();
    return name.skip(before: (char('@') & char('.')).flatten());
  }

  /// Literal value in a filter: string, number, true, false, null
  Parser<String> _literal() => [
        quotedString,
        number.flatten(),
        string('true'),
        string('false'),
        string('null'),
      ].toChoiceParser().cast<String>();

  // -- Slice / Index / Union disambiguation --

  /// Disambiguates `[0:5]` (slice), `[0]` (index), `[0, 2]` (union),
  /// `['name']` (child), `['name', 'kind']` (union)
  Parser<JsonPathSegment> _sliceOrIndexOrUnion() {
    return _unionElements().map2((elements, pos) {
      if (elements.length == 1) {
        final e = elements.first;
        return switch (e) {
          _SliceElement() => ArraySliceSegment(
              start: e.start, end: e.end, step: e.step, position: pos),
          _IntElement() => ArrayIndexSegment(e.value, pos),
          _NameElement() => DotNameSegment(e.name, pos),
        };
      }

      // Multiple elements — build Union
      final unionElements = <UnionElement>[];
      for (final e in elements) {
        switch (e) {
          case _IntElement():
            unionElements.add(IndexElement(e.value));
          case _NameElement():
            unionElements.add(FieldNameElement(e.name));
          case _SliceElement():
            // Slices in union — treat first element as slice
            return ArraySliceSegment(
                start: e.start, end: e.end, step: e.step, position: pos);
        }
      }
      return UnionSegment(unionElements, pos);
    });
  }

  Parser<List<_UnionElement>> _unionElements() =>
      _unionElement().toList();

  Parser<_UnionElement> _unionElement() => [
        _sliceElement(),
        _intElement(),
        _nameElement(),
      ].toChoiceParser().trim();

  /// `start:stop` or `start:stop:step`
  Parser<_SliceElement> _sliceElement() {
    final colon = char(':').trim();
    final optInt = integer.optional();
    return (optInt & optInt.skip(before: colon) & optInt.skip(before: colon).optional())
        .map((v) => _SliceElement(v[0] as int?, v[1] as int?, v[2] as int?));
  }

  /// Integer element
  Parser<_IntElement> _intElement() =>
      integer.map((v) => _IntElement(v));

  /// Quoted string element
  Parser<_NameElement> _nameElement() =>
      quotedString.map((v) => _NameElement(v));

  // -- Helpers --

  /// Member name shorthand (reuses the pattern from strings.dart but without childSelector mapping)
  Parser<String> _memberName() {
    final nameFirst = (char('_') | letter() |
            range(String.fromCharCode(0x80), String.fromCharCode(0xFFFF)))
        .plus()
        .flatten();
    final nameChar = digit() | nameFirst;
    return (nameFirst & nameChar.star()).flatten();
  }

  static String _reverseOp(String op) => switch (op) {
        '<' => '>',
        '>' => '<',
        '<=' => '>=',
        '>=' => '<=',
        _ => op,
      };
}

/// Extension to capture position during mapping.
extension _PositionMap<R> on Parser<R> {
  Parser<T> map2<T>(T Function(R value, int position) mapper) =>
      _PositionMapParser(this, mapper);
}

class _PositionMapParser<T, R> extends DelegateParser<R, T> {
  final T Function(R, int) _mapper;

  _PositionMapParser(super.delegate, this._mapper);

  @override
  Result<T> parseOn(Context context) {
    final result = delegate.parseOn(context);
    if (result is Success<R>) {
      return result.success(_mapper(result.value, context.position));
    }
    return result.failure(result.message);
  }

  @override
  _PositionMapParser<T, R> copy() =>
      _PositionMapParser<T, R>(delegate, _mapper);
}

// -- Internal disambiguation types --

sealed class _UnionElement {}

class _IntElement extends _UnionElement {
  final int value;
  _IntElement(this.value);
}

class _NameElement extends _UnionElement {
  final String name;
  _NameElement(this.name);
}

class _SliceElement extends _UnionElement {
  final int? start;
  final int? end;
  final int? step;
  _SliceElement(this.start, this.end, this.step);
}

class _Comparable {
  final String value;
  final bool isPath;
  _Comparable(this.value, {required this.isPath});
}

class _FilterGroup {
  final List<FilterFieldRef> fieldRefs;
  final FilterLogicalOperator operator;
  _FilterGroup(this.fieldRefs, this.operator);
}
