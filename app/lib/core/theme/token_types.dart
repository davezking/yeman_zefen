import 'dart:ui';

/// An inset shadow from tokens.json. Flutter's BoxShadow cannot be inset, so
/// the widgets paint these as a highlight along the top edge (see InsetGloss).
class InsetShadow {
  const InsetShadow({
    required this.color,
    required this.dx,
    required this.dy,
    required this.blur,
  });

  final Color color;
  final double dx;
  final double dy;
  final double blur;
}

/// Fully transparent. Not a design color: it only switches off Material's
/// default splash and highlight where the designed press effect replaces them.
const transparentColor = Color(0x00000000);
