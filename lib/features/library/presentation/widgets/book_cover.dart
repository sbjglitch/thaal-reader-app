import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_tokens.dart';
import '../../../../app/theme/app_radius_tokens.dart';
import '../../../../domain/entities/enums.dart';

/// Cover thumbnail with a neutral fallback (UI/UX spec §7.1, §8).
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.format,
    this.file,
    this.width = 48,
    this.height = 68,
  });

  final PublicationFormat format;
  final File? file;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTokens;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: AppRadius.smallAll,
      ),
      child: Center(
        child: Icon(
          format == PublicationFormat.pdf
              ? Icons.picture_as_pdf_outlined
              : Icons.menu_book_outlined,
          color: colors.textTertiary,
        ),
      ),
    );
    final image = file;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: image == null
            ? fallback
            : ClipRRect(
                borderRadius: AppRadius.smallAll,
                child: Image.file(
                  image,
                  fit: BoxFit.cover,
                  // Decode near display size to keep memory low in long lists.
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  errorBuilder: (_, _, _) => fallback,
                ),
              ),
      ),
    );
  }
}
