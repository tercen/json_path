import 'package:tercen_json_path/src/expression/expression.dart';
import 'package:tercen_json_path/src/expression/static_expression.dart';
import 'package:tercen_json_path/src/node.dart';
import 'package:maybe_just_nothing/maybe_just_nothing.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('Expression', () {
    group('Static', () {
      final node = Node('foo');
      final s = StaticExpression(const Just('bar'));
      final d = Expression((Node n) => Future.value(Just(n.value)));
      test('map()', () async {
        expect(
          await s
              .map((v) => Future.value(v.map((v) => '$v!').or('oops')))
              .call(node),
          'bar!',
        );
      });
      test('merge() with non-static', () async {
        expect(
          await s
              .merge(
                d,
                (v, m) => Future.value(v.merge(m, (a, b) => '$a$b').or('oops')),
              )
              .call(node),
          'barfoo',
        );
      });
    });
  });
}
