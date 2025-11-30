import 'package:tercen_json_path/fun_sdk.dart';

/// Returns the index at which the node referenced by the argument
/// is found in the parent array.
/// If the parent is not an array, returns [Nothing].
/// Requires a singular node stream (compile-time validated).
class Index implements Fun1<Maybe, SingularNodeStream> {
  const Index();

  @override
  final name = 'index';

  @override
  Future<Maybe> call(SingularNodeStream nodes) async {
    // Type system guarantees exactly one node!
    final node = nodes.node;
    return Just(node.index).type<int>();
  }
}
