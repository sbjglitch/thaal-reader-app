/// Reading theme for the publication surface, independent of the app theme
/// (UI/UX §3.4).
enum ReadingTheme { system, light, dark }

/// How pages advance.
enum PageLayout { paginated, scroll }

/// How a PDF page is scaled to the screen.
enum PdfPageFit { width, page }

/// Reading preferences, applied to every book (UI/UX §7.6). They are global
/// defaults only: there are no per-book overrides in the MVP, so this is the
/// single source of truth.
final class ReaderPreferences {
  const ReaderPreferences({
    this.theme = ReadingTheme.system,
    double fontScale = defaultFontScale,
    this.epubLayout = PageLayout.paginated,
    this.pdfLayout = PageLayout.paginated,
    this.pdfFit = PdfPageFit.width,
  }) : fontScale = fontScale < minFontScale
           ? minFontScale
           : (fontScale > maxFontScale ? maxFontScale : fontScale);

  static const double minFontScale = 0.8;
  static const double maxFontScale = 2.0;
  static const double defaultFontScale = 1.0;

  /// Applies to EPUB only.
  final ReadingTheme theme;

  /// EPUB text size relative to the publication's own size, clamped to
  /// [minFontScale]–[maxFontScale].
  final double fontScale;
  final PageLayout epubLayout;
  final PageLayout pdfLayout;
  final PdfPageFit pdfFit;

  ReaderPreferences copyWith({
    ReadingTheme? theme,
    double? fontScale,
    PageLayout? epubLayout,
    PageLayout? pdfLayout,
    PdfPageFit? pdfFit,
  }) {
    return ReaderPreferences(
      theme: theme ?? this.theme,
      fontScale: fontScale ?? this.fontScale,
      epubLayout: epubLayout ?? this.epubLayout,
      pdfLayout: pdfLayout ?? this.pdfLayout,
      pdfFit: pdfFit ?? this.pdfFit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPreferences &&
      other.theme == theme &&
      other.fontScale == fontScale &&
      other.epubLayout == epubLayout &&
      other.pdfLayout == pdfLayout &&
      other.pdfFit == pdfFit;

  @override
  int get hashCode =>
      Object.hash(theme, fontScale, epubLayout, pdfLayout, pdfFit);
}
