/// Reading theme for the publication surface, independent of the app theme
/// (UI/UX §3.4). Sepia and twilight are fixed page colours that do not follow
/// the app theme.
enum ReadingTheme { system, light, dark, sepia, twilight }

/// How pages advance.
enum PageLayout { paginated, scroll }

/// How a PDF page is scaled to the screen.
enum PdfPageFit { width, page }

/// EPUB text alignment. [original] keeps the publication's own styles;
/// the others override them. [start] is left-aligned in left-to-right text.
enum TextAlignment { original, start, justify }

/// EPUB font. [original] keeps the publication's fonts; [serif] and
/// [sansSerif] use the device's own fonts of that kind, so nothing is
/// bundled.
enum FontFace { original, serif, sansSerif }

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
    double pageMargins = defaultPageMargins,
    this.textAlignment = TextAlignment.original,
    this.fontFace = FontFace.original,
  }) : fontScale = fontScale < minFontScale
           ? minFontScale
           : (fontScale > maxFontScale ? maxFontScale : fontScale),
       pageMargins = pageMargins < minPageMargins
           ? minPageMargins
           : (pageMargins > maxPageMargins ? maxPageMargins : pageMargins);

  static const double minFontScale = 0.8;
  static const double maxFontScale = 2.0;
  static const double defaultFontScale = 1.0;

  static const double minPageMargins = 0.5;
  static const double maxPageMargins = 2.0;
  static const double defaultPageMargins = 1.0;

  /// Applies to EPUB only.
  final ReadingTheme theme;

  /// EPUB text size relative to the publication's own size, clamped to
  /// [minFontScale]–[maxFontScale].
  final double fontScale;
  final PageLayout epubLayout;
  final PageLayout pdfLayout;
  final PdfPageFit pdfFit;

  /// EPUB side margins relative to the engine's default (1.0), clamped to
  /// [minPageMargins]–[maxPageMargins].
  final double pageMargins;

  /// Applies to EPUB only.
  final TextAlignment textAlignment;

  /// Applies to EPUB only.
  final FontFace fontFace;

  ReaderPreferences copyWith({
    ReadingTheme? theme,
    double? fontScale,
    PageLayout? epubLayout,
    PageLayout? pdfLayout,
    PdfPageFit? pdfFit,
    double? pageMargins,
    TextAlignment? textAlignment,
    FontFace? fontFace,
  }) {
    return ReaderPreferences(
      theme: theme ?? this.theme,
      fontScale: fontScale ?? this.fontScale,
      epubLayout: epubLayout ?? this.epubLayout,
      pdfLayout: pdfLayout ?? this.pdfLayout,
      pdfFit: pdfFit ?? this.pdfFit,
      pageMargins: pageMargins ?? this.pageMargins,
      textAlignment: textAlignment ?? this.textAlignment,
      fontFace: fontFace ?? this.fontFace,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPreferences &&
      other.theme == theme &&
      other.fontScale == fontScale &&
      other.epubLayout == epubLayout &&
      other.pdfLayout == pdfLayout &&
      other.pdfFit == pdfFit &&
      other.pageMargins == pageMargins &&
      other.textAlignment == textAlignment &&
      other.fontFace == fontFace;

  @override
  int get hashCode => Object.hash(
    theme,
    fontScale,
    epubLayout,
    pdfLayout,
    pdfFit,
    pageMargins,
    textAlignment,
    fontFace,
  );
}

/// Screen brightness while reading. It is separate from
/// [ReaderPreferences] because it never reaches the reader engine, and it
/// is not backed up: the right level depends on the device's screen.
final class ReaderBrightness {
  const ReaderBrightness({
    this.followsSystem = true,
    double level = defaultLevel,
  }) : level = level < minLevel
           ? minLevel
           : (level > maxLevel ? maxLevel : level);

  /// Low enough for reading in the dark without the page disappearing.
  static const double minLevel = 0.05;
  static const double maxLevel = 1.0;
  static const double defaultLevel = 0.5;

  /// The system (and auto-brightness, if on) decides; [level] is kept for
  /// when the user turns this off again.
  final bool followsSystem;

  /// The chosen window brightness, clamped to [minLevel]–[maxLevel].
  final double level;

  @override
  bool operator ==(Object other) =>
      other is ReaderBrightness &&
      other.followsSystem == followsSystem &&
      other.level == level;

  @override
  int get hashCode => Object.hash(followsSystem, level);
}
