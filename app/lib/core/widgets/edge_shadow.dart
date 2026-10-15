import 'package:flutter/painting.dart';

import '../theme/tokens.dart';

/// A solid "press edge" under a surface and nothing else, in [color]: the
/// shadow for segmented-control items, genre chips and other flat raised bits.
/// [RaisedSurface] moves down by [dy] when pressed.
List<BoxShadow> edgeShadow(Color color, {double dy = SpacingTokens.n4}) => [
  BoxShadow(color: color, offset: Offset(0, dy)),
];
