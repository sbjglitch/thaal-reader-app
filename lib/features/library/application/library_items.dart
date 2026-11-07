import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/book.dart';

/// A book as shown in the library, with its file availability resolved.
final class LibraryItem {
  const LibraryItem({
    required this.book,
    required this.fileAvailable,
    this.coverFile,
    this.progression,
  });

  final Book book;

  /// False when the publication file is missing from app-private storage.
  /// The record is kept and shown as unavailable (a recoverable state).
  final bool fileAvailable;
  final File? coverFile;

  /// Approximate reading progress, 0.0–1.0, once the book has been read.
  final double? progression;
}

/// Saved progressions by book ID, for display and sorting.
final readingProgressionsProvider = StreamProvider<Map<String, double>>(
  (ref) => ref.watch(readingProgressRepositoryProvider).watchProgressions(),
);

/// All books, newest first, re-emitted whenever the library changes.
final libraryItemsProvider = StreamProvider<List<LibraryItem>>((ref) {
  final storage = ref.watch(libraryStorageProvider);
  // Progress is decoration: the library still shows while it loads or fails.
  final progressions = ref.watch(readingProgressionsProvider).value ?? const {};
  return ref.watch(bookRepositoryProvider).watchBooks().asyncMap((books) {
    return Future.wait([
      for (final book in books)
        storage.exists(book.filePath).then((available) {
          final cover = book.coverPath;
          return LibraryItem(
            book: book,
            fileAvailable: available,
            coverFile: cover == null ? null : storage.file(cover),
            progression: progressions[book.id],
          );
        }),
    ]);
  });
});
