import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'tools/config.dart';
import 'tools/notification_navigation.dart';
import 'tools/notification_service.dart';
import 'tools/routes.dart';
import 'widgets/biometric_lock_layer.dart';

void main() async {
  // 初始化数据之前，需要调用WidgetsFlutterBinding.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化数据之后再加载UI，以及账单监听服务
  await Global.init();
  await NotificationService().initNotification();
  final initialNotificationPayload =
      await NotificationService().getNotificationLaunchPayload();
  await initializeDateFormatting();

  runApp(MyApp(initialNotificationPayload: initialNotificationPayload));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.initialNotificationPayload});

  final String? initialNotificationPayload;

  @override
  State<StatefulWidget> createState() {
    return MyAppState();
  }
}

class MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final NotificationNavigation _notificationNavigation;
  late final StreamSubscription<String?> _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _notificationNavigation = NotificationNavigation(_navigatorKey);
    _notificationSubscription = selectNotificationStream.stream.listen(
      _openNotificationDestination,
    );

    if (widget.initialNotificationPayload == '/home/schedule') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        selectNotificationStream.add(widget.initialNotificationPayload);
      });
    }
  }

  void _openNotificationDestination(String? payload) {
    if (_notificationNavigation.open(payload)) {
      return;
    }

    if (NotificationNavigation.directRouteForPayload(payload) == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notificationNavigation.open(payload);
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    super.dispose();
  }

  String get _initialRoute {
    if (!Global.jumpLoad) {
      return '/';
    }

    return NotificationNavigation.directRouteForPayload(
          widget.initialNotificationPayload,
        ) ??
        '/';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '记账',
      theme: ThemeData(useMaterial3: false),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', ''), Locale('zh', '')],
      locale: const Locale('zh', ''),
      initialRoute: _initialRoute,
      onGenerateRoute: onGenerateRoute,
      builder: (context, child) {
        return BiometricLockLayer(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
