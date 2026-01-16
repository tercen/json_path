import 'package:tercen_json_path/src/grammar/slice_indices.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart';
import 'package:tercen_json_path/src/virtual_property_resolver.dart';

/// A JSON document node.
class Node<T extends Object?> {
  /// Creates an instance of the root node of the JSON document [value].
  Node(
    this.value, {
    VirtualHierarchyResolver? resolver,
    VirtualHierarchyContext? context,
    VirtualPropertyResolver? virtualPropertyResolver,
  })  : parent = null,
        key = null,
        index = null,
        _resolver = resolver,
        _context = context,
        _virtualPropertyResolver = virtualPropertyResolver;

  /// Creates an instance of a child node.
  Node._(
    this.value,
    this.parent, {
    this.key,
    this.index,
    VirtualHierarchyResolver? resolver,
    VirtualHierarchyContext? context,
    VirtualPropertyResolver? virtualPropertyResolver,
  })  : _resolver = resolver ?? parent?._resolver,
        _context = context ?? parent?._context,
        _virtualPropertyResolver =
            virtualPropertyResolver ?? parent?._virtualPropertyResolver;

  /// The node value.
  final T value;

  /// The parent node.
  final Node? parent;

  /// Virtual hierarchy resolver for lazy collection fetching
  final VirtualHierarchyResolver? _resolver;

  /// Context for virtual hierarchy resolution
  final VirtualHierarchyContext? _context;

  /// Virtual property resolver for computed properties
  final VirtualPropertyResolver? _virtualPropertyResolver;

  /// The root node of the entire document.
  Node get root => parent?.root ?? this;

  /// For a node which is an object child, this is its [key] in the [parent]
  /// node.
  final String? key;

  /// For a node which is an element of an array, this is its [index]
  /// in the [parent] node.
  final int? index;

  /// For a node whose value is an array, returns the slice of
  /// its children.
  Stream<Node>? slice({int? start, int? stop, int? step}) {
    final v = value;
    if (v is List) {
      return Stream.fromIterable(
        sliceIndices(
          v.length,
          start,
          stop,
          step ?? 1,
        ).map((index) => _element(v, index)),
      );
    }
    return null;
  }

  /// All direct children of the node.
  Stream<Node> get children async* {
    final v = value;
    if (v is Map) {
      for (final key in v.keys) {
        yield _child(v, key);
      }
    }
    if (v is List) {
      for (final entry in v.asMap().entries) {
        yield _element(v, entry.key);
      }
    }
  }

  /// Returns the JSON array element at the [offset] if it exists,
  /// otherwise returns null. Negative offsets are supported.
  Future<Node?> element(int offset) async {
    final v = value;
    if (v is List) {
      final index = offset < 0 ? v.length + offset : offset;
      if (index >= 0 && index < v.length) return _element(v, index);
    }
    return null;
  }

  /// Returns the JSON object child at the [key] if it exists,
  /// otherwise returns null.
  Future<Node?> child(String key) async {
    final v = value;

    // Try to get from existing data first (fast path)
    if (v is Map && v.containsKey(key)) return _child(v, key);

    // Try virtual property resolution (computed properties within document)
    if (_virtualPropertyResolver != null &&
        v is Map<String, dynamic> &&
        _virtualPropertyResolver!.isVirtualProperty(key)) {
      final rootValue = root.value;
      if (rootValue is Map<String, dynamic>) {
        final resolved = await _virtualPropertyResolver!.resolveProperty(
          v,
          rootValue,
          key,
        );
        if (resolved != null) {
          return _createVirtualChild(key, resolved);
        }
      }
    }

    // Try virtual collection resolution (external documents)
    if (_resolver != null && _isVirtualCollection(key)) {
      final context = VirtualHierarchyContext(
        parentCollection: _inferCollectionFromNode(),
        parentId: _extractIdFromNode(),
      );

      final docs = await _resolver!.resolveCollection(key, context);

      if (docs.isNotEmpty) {
        // Create virtual child with fetched data
        return _createVirtualChild(key, docs);
      }
    }

    return null;
  }

  Node _element(List list, int index) => Node._(
        list[index],
        this,
        index: index,
        resolver: _resolver,
        context: _context,
        virtualPropertyResolver: _virtualPropertyResolver,
      );

  Node _child(Map map, String key) => Node._(
        map[key],
        this,
        key: key,
        resolver: _resolver,
        context: _context,
        virtualPropertyResolver: _virtualPropertyResolver,
      );

  /// Check if a key represents a virtual collection
  bool _isVirtualCollection(String key) {
    return const [
      'projects',
      'teams',
      'workflows',
      'schemas',
      'files',
      'folders',
      'operators',
      'tasks',
      'users',
      'projectDocuments',
      'objects',
      'documents',
    ].contains(key);
  }

  /// Infer collection type from current node
  String? _inferCollectionFromNode() {
    final v = value;
    if (v is Map) {
      final kind = v['kind'] as String?;
      return _mapKindToCollection(kind);
    }
    return null;
  }

  /// Map document kind to collection name
  String? _mapKindToCollection(String? kind) {
    if (kind == null) return null;

    switch (kind) {
      case 'Project':
        return 'projects';
      case 'Team':
        return 'teams';
      case 'Workflow':
        return 'workflows';
      case 'TableSchema':
      case 'CubeQueryTableSchema':
      case 'ComputedTableSchema':
        return 'schemas';
      case 'FileDocument':
        return 'files';
      case 'FolderDocument':
        return 'folders';
      case 'Operator':
      case 'GitOperator':
      case 'DockerOperator':
      case 'ROperator':
      case 'WebAppOperator':
        return 'operators';
      case 'Task':
      case 'ProjectTask':
      case 'RunComputationTask':
      case 'SaveComputationResultTask':
      case 'ComputationTask':
      case 'CubeQueryTask':
      case 'CSVTask':
      case 'RunWorkflowTask':
      case 'RunWebAppTask':
      case 'ImportGitWorkflowTask':
      case 'ExportWorkflowTask':
      case 'ImportGitDatasetTask':
      case 'ExportTableTask':
      case 'TestOperatorTask':
      case 'GitProjectTask':
      case 'LibraryTask':
      case 'GlTask':
      case 'CreateGitOperatorTask':
        return 'tasks';
      case 'User':
        return 'users';
      default:
        return null;
    }
  }

  /// Extract ID from current node
  String? _extractIdFromNode() {
    final v = value;
    if (v is Map) {
      return v['id'] as String?;
    }
    return null;
  }

  /// Create a virtual child node with resolved data
  Node _createVirtualChild(String key, dynamic resolvedValue) {
    // Inject the resolved value into parent's value
    final parentValue = value as Map;
    final updatedValue = Map<String, dynamic>.from(parentValue);
    updatedValue[key] = resolvedValue;

    // Create a new node with updated value and return the child
    final updatedParent = Node._(
      updatedValue,
      parent,
      key: this.key,
      index: index,
      resolver: _resolver,
      context: _context,
      virtualPropertyResolver: _virtualPropertyResolver,
    );

    return Node._(
      resolvedValue,
      updatedParent,
      key: key,
      resolver: _resolver,
      context: _context,
      virtualPropertyResolver: _virtualPropertyResolver,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Node &&
      other.value == value &&
      other.parent == parent &&
      other.index == index &&
      other.key == key;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Node($value)';
}
