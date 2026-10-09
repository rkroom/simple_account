import 'package:flutter/material.dart';

class NotificationNavigation {
  NotificationNavigation(this.navigatorKey);

  static const String pendingBillRoute = '/billListener';
  static const String statisticRoute = '/statistic';

  final GlobalKey<NavigatorState> navigatorKey;

  static String? directRouteForPayload(String? payload) {
    return switch (payload) {
      pendingBillRoute => pendingBillRoute,
      statisticRoute => statisticRoute,
      _ => null,
    };
  }

  bool open(String? payload) {
    final route = directRouteForPayload(payload);
    final navigator = navigatorKey.currentState;
    if (route == null || navigator == null) {
      return false;
    }

    navigator.pushNamed(route);
    return true;
  }
}
