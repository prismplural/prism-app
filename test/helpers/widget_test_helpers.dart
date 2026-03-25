import 'package:flutter/material.dart';

/// Wraps a widget in MaterialApp + Scaffold for widget testing.
Widget testApp(Widget child, {bool center = true, ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: center ? Center(child: child) : child,
    ),
  );
}
