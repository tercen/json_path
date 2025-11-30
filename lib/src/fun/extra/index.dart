import 'package:tercen_json_path/fun_sdk.dart';

/// Returns the index at which the node referenced by the argument
/// is found in the parent array.
/// If the parent is not an array, returns [Nothing].
/// If the argument does not reference a single node, returns [Nothing].
class Index implements Fun1<Maybe, NodeList> {
  const Index();

  @override
  final name = 'index';

  @override
  Future<Maybe> call(NodeList nodes) async {
    final list = await nodes.toList();
    if (list.length != 1) return const Nothing();
    final node = list.first;
    return Just(node.index).type<int>();
  }
}
