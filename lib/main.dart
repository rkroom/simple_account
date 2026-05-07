import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'tools/config.dart';
import 'tools/routes.dart';
import 'widgets/biometric_lock_layer.dart';

void main() async {
  // 初始化数据之前，需要调用WidgetsFlutterBinding.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化数据之后再加载UI，以及账单监听服务
  await Global.init();

  initializeDateFormatting().then((_) => runApp(const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() {
    return MyAppState();
  }
}

class MyAppState extends State<MyApp> {
  // 默认进入的页面
  String firstPage = '/';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记账',
      theme: ThemeData(useMaterial3: false),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', ''), Locale('zh', '')],
      locale: const Locale('zh', ''),
      initialRoute: firstPage,
      onGenerateRoute: onGenerateRoute,
      builder: (context, child) {
        return BiometricLockLayer(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
