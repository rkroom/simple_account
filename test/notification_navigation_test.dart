import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/tools/notification_navigation.dart';

void main() {
  testWidgets('pending bill payload opens the bill listener route', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final navigation = NotificationNavigation(navigatorKey);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Text('home'),
        routes: {
          NotificationNavigation.pendingBillRoute:
              (_) => const Text('bill listener'),
        },
      ),
    );

    expect(navigation.open(NotificationNavigation.pendingBillRoute), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('bill listener'), findsOneWidget);
  });

  testWidgets('unknown payload does not navigate', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final navigation = NotificationNavigation(navigatorKey);

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
    );

    expect(navigation.open('/unknown'), isFalse);
    await tester.pump();

    expect(find.text('home'), findsOneWidget);
  });
}
