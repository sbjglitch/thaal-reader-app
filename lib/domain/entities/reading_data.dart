import 'enums.dart';
import 'locator_envelope.dart';

/// Latest restorable position for a book (DATABASE_SCHEMA.md §5.2).
///
/// [locator] is the restoration source; [pageNumber] and [progression] are
/// supplementary display fields, not restoration keys.
final class ReadingProgress {
  ReadingProgress({
    required this.bookId,
    this.locator,
    this.pageNumber,
    this.progression,
    required this.updatedAt,
  }) {
    if (progression case final value?
        when value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(progression, 'progression', 'must be 0.0–1.0');
    }
    if (pageNumber case final page? when page < 1) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'must be ≥ 1');
    }
  }

  final String bookId;
  final SerializedLocator? locator;

  /// One-based page number, primarily for PDF.
  final int? pageNumber;
  final double? progression;
  final DateTime updatedAt;
}

/// A user-saved location (DATABASE_SCHEMA.md §5.3).
final class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.locator,
    this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final SerializedLocator locator;
  final String? label;
  final DateTime createdAt;
  final DateTime updatedAt;

  Bookmark copyWith({String? label, required DateTime updatedAt}) {
    return Bookmark(
      id: id,
      bookId: bookId,
      locator: locator,
      label: label ?? this.label,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// An EPUB text highlight with an optional note (DATABASE_SCHEMA.md §5.4).
///
/// [selectedText] and [note] are private reading content: never log them.
final class Highlight {
  const Highlight({
    required this.id,
    required this.bookId,
    required this.locator,
    this.selectedText,
    required this.color,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final SerializedLocator locator;
  final String? selectedText;
  final HighlightColor color;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A user-created group of books (DATABASE_SCHEMA.md §5.5). Duplicate names
/// are allowed (§14).
final class Collection {
  Collection({
    required this.id,
    required String name,
    required this.createdAt,
    required this.updatedAt,
  }) : name = name.trim() {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}
