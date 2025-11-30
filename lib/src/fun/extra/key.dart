import 'package:tercen_json_path/fun_sdk.dart';

/// Returns the key under which the node referenced by the argument
/// is found in the parent object.
/// If the parent is not an object, returns [Nothing].
/// If the argument does not reference a single node, returns [Nothing].
///
/// TODO: Requires async refactoring to work with Stream<Node>
class Key implements Fun1<Maybe, NodeList> {
  const Key();

  @override
  final name = 'key';

  @override
  Maybe call(NodeList nodes) {
    throw UnimplementedError('key() requires async Stream support');
  }
}
