import 'package:flutter/material.dart';

class AppSpacing {
  static const double hairline = 1.0;
  static const double textTight = 1.0;
  static const double textStack = 2.0;
  static const double micro = textStack * 2;
  static const double iconTight = 5.0;
  static const double stackTight = 6.0;
  static const double controlTight = 6.0;
  static const double compact = 8.0;
  static const double fieldGap = 10.0;
  static const double tileY = 10.0;
  static const double tileX = 12.0;
  static const double stack = 12.0;
  static const double card = 14.0;
  static const double block = 16.0;
  static const double section = block + compact;
  static const double shell = block * 2;
  static const double screenX = 18.0;
  static const double screenBottom = 18.0;
  static const double screenTop = 28.0;
  static const double insetWide = screenX + tileX;

  static const double radiusScreen = 28.0;
  static const double radiusCard = 14.0;
  static const double radiusTile = 12.0;
  static const double radiusControl = 10.0;
  static const double radiusCapsule = 8.0;
  static const double radiusPanel = radiusCard + micro;
  static const double radiusHero = radiusScreen - micro;
  static const double radiusPill = 999.0;
  static const double contentMaxWidth = 620.0;

  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(
    screenX,
    screenTop,
    screenX,
    screenBottom,
  );
  static const EdgeInsets cardPadding = EdgeInsets.all(card);
  static const EdgeInsets blockPadding = EdgeInsets.all(block);
  static const EdgeInsets tilePadding = EdgeInsets.symmetric(
    vertical: tileY,
    horizontal: tileX,
  );
  static const EdgeInsets capsulePadding = EdgeInsets.symmetric(
    horizontal: tileX,
    vertical: controlTight,
  );
}
