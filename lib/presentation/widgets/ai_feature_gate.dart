import 'package:flutter/material.dart';
import '../../application/services/ai/ai_service.dart';
import '../screens/setup/setup_required_screen.dart';

Future<bool> ensureFeatureAiReady(
  BuildContext context, {
  AIService? service,
}) async {
  final ai = service ?? AIService();
  if (ai.isInitialized) return true;
  return await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (ctx) => SetupRequiredScreen(
            ai: ai,
            aiOnly: true,
            onComplete: (ctx) => Navigator.pop(ctx, true),
          ),
        ),
      ) ??
      false;
}
