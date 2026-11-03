import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expencify/presentation/screens/auth/onboarding_screen.dart';

void main() {
  testWidgets('Onboarding presents the introduction', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Welcome to Spendy'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
