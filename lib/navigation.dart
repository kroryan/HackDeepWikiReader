import 'package:flutter/material.dart';

/// Shared root Navigator key -- lets widgets mounted above the Navigator
/// (see main.dart's MaterialApp.builder + ChatOverlayHost, which sits
/// alongside the Navigator rather than inside it) still push routes, since
/// Navigator.of(context) can't find a Navigator that isn't an ancestor.
final rootNavigatorKey = GlobalKey<NavigatorState>();
