import 'package:flutter/material.dart';
import 'package:simple_account/pages/bill_listener.dart';
import 'package:simple_account/pages/bill_listener_config.dart';
import 'package:simple_account/pages/configuration.dart';
import 'package:simple_account/pages/statistic.dart';

import '../pages/home.dart';
import '../pages/loading.dart';
import '../pages/manage.dart';
import '../pages/auth_gate.dart';
import 'config.dart';

final Map<String, Function> routes = {
  '/': (context) {
    if (!Global.jumpLoad) {
      return const LoadingWidget();
    }

    if (Global.biometricUnlockEnabled) {
      return const AuthGateWidget();
    }

    return HomeWidget();
  },
  '/home': (context) => HomeWidget(),
  '/createdb': (context) => const CreateDatabaseWidget(),
  // arguments传递参数
  '/selectdb':
      (context, {arguments}) => SelectDatabaseWidget(arguments: arguments),
  '/manage': (context) => const ManageWidget(),
  '/accountFile': (context) => const LoadingWidget(),
  '/billListener': (context) => const BillListenerWidget(),
  '/statistic': (context) => const StatisticWidget(),
  '/configuration': (context) => const ConfigurationWidget(),
  '/billListenerConfig':
      (context, {arguments}) => BillListenerConfigWidget(arguments: arguments),
};

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final String? name = settings.name;
  if (name == null) return null;

  final Function? pageContentBuilder = routes[name];

  if (pageContentBuilder != null) {
    if (settings.arguments != null) {
      return MaterialPageRoute(
        builder:
            (context) =>
                pageContentBuilder(context, arguments: settings.arguments),
      );
    } else {
      return MaterialPageRoute(
        builder: (context) => pageContentBuilder(context),
      );
    }
  }

  return null;
}
