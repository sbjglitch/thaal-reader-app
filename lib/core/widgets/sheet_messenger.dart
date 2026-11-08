import 'package:flutter/material.dart';

/// Gives a modal bottom sheet its own snack bars. Without it, a snack bar
/// (and its Undo) appears behind the sheet, where tapping it closes the
/// sheet instead. Use inside a sheet whose height is already fixed, such as
/// a `DraggableScrollableSheet` builder.
class SheetMessenger extends StatelessWidget {
  const SheetMessenger({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(backgroundColor: Colors.transparent, body: child),
    );
  }
}
