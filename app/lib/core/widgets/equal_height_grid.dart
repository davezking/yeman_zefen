import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A grid whose rows are as tall as their tallest child, so the two answers
/// beside each other always match and grow together when text is long (Amharic)
/// or the text scale is 1.3. A fixed-aspect-ratio grid cannot do that: it clips.
///
/// Used for the 2 x 2 answers and the era cards. Children should fill their
/// cell's height (the designed tiles and cards do).
class EqualHeightGrid extends StatelessWidget {
  const EqualHeightGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.spacing = SpacingTokens.n12,
  });

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final cells = <Widget>[];
      for (var i = 0; i < columns; i++) {
        if (i > 0) cells.add(SizedBox(width: spacing));
        final index = start + i;
        // A missing last cell keeps the column width.
        cells.add(
          Expanded(
            child: index < children.length
                ? children[index]
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
