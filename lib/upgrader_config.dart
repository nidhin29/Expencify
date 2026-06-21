import 'package:upgrader/upgrader.dart';

final Upgrader appUpgrader = Upgrader(
  debugDisplayAlways: false,
  debugLogging: false,
  durationUntilAlertAgain: const Duration(hours: 4),
);
