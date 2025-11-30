/// Interface for resolving RefId references to their target objects.
///
/// This is used by the @ dereferencing operator to fetch referenced documents
/// from external sources (e.g., CouchDB).
///
/// Example:
/// ```dart
/// class CouchDBResolver implements RefIdResolver {
///   final CouchDBClient db;
///   CouchDBResolver(this.db);
///
///   @override
///   Future<Map<String, dynamic>?> dereference(String refId, String targetKind) async {
///     try {
///       return await db.get(refId);
///     } catch (e) {
///       return null; // Document not found
///     }
///   }
/// }
/// ```
abstract class RefIdResolver {
  /// Resolves a RefId value to its target object.
  ///
  /// Parameters:
  /// - [refId]: The reference ID string (e.g., "op_abc123")
  /// - [targetKind]: The expected kind/type of the target document (e.g., "Operator")
  ///
  /// Returns:
  /// - The resolved document as a Map, or null if not found or invalid
  ///
  /// The resolver should:
  /// 1. Fetch the document with the given [refId]
  /// 2. Optionally verify that the document's kind matches [targetKind]
  /// 3. Return the document as a Map<String, dynamic>
  /// 4. Return null if the document doesn't exist or validation fails
  Future<Map<String, dynamic>?> dereference(String refId, String targetKind);
}
