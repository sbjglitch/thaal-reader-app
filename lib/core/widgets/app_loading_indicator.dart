import 'package:flutter/material.dart';

/// Restrained, centred loading feedback with an accessible label.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.semanticsLabel = 'Loading'});

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(semanticsLabel: semanticsLabel),
    );
  }
}
