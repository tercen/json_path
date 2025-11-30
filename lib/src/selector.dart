import 'package:tercen_json_path/fun_sdk.dart';
import 'package:tercen_json_path/src/expression/node_stream.dart';

// Re-export so selector files have access
export 'package:tercen_json_path/src/expression/node_stream.dart';

/// A selector that transforms a stream of nodes into another stream.
/// Can return zero or more nodes.
typedef Selector = NodeStream Function(NodeStream nodes);

/// A selector that is guaranteed to return exactly one node.
/// Used for selectors like @ in filter contexts.
typedef SingularSelector = SingularNodeStream Function(SingularNodeStream node);
