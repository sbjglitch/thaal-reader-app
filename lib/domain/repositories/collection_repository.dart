import '../entities/reading_data.dart';

abstract interface class CollectionRepository {
  /// All collections ordered by name.
  Stream<List<Collection>> watchCollections();

  Future<void> createCollection(Collection collection);

  Future<void> renameCollection(String collectionId, String name);

  /// Deletes the collection and its membership links; books are kept.
  Future<void> deleteCollection(String collectionId);

  /// Adding a book that is already a member is a no-op.
  Future<void> addBookToCollection(String collectionId, String bookId);

  Future<void> removeBookFromCollection(String collectionId, String bookId);

  /// IDs of the books in [collectionId], in the order they were added.
  Stream<List<String>> watchBookIds(String collectionId);
}
