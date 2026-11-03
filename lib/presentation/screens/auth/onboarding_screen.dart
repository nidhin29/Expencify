import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../application/services/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';
import '../setup/setup_required_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _authService = AuthService();
  bool _opening = false;
  void _goToHome() async {
    if (_opening) return;
    setState(() => _opening = true);
    await _authService.setOnboarded();
    if (!mounted) return;

    // Check Requirements before opening Home
    final prefs = await SharedPreferences.getInstance();
    final legalAccepted = prefs.getBool('legal_terms_accepted') ?? false;
    final requirementsMet = legalAccepted;

    if (!mounted) return;

    if (!requirementsMet) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SetupRequiredScreen(
            onComplete: (ctx) {
              Navigator.of(ctx).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
          ),
        ),
      );
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  Widget _benefit(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: cs.surface,
                systemNavigationBarColor: cs.surface,
                systemNavigationBarIconBrightness:
                    theme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
      child: Scaffold(
        backgroundColor: cs.surface,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: FilledButton(
              onPressed: _opening ? null : _goToHome,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_opening ? 'Opening…' : 'Get started'),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(AppIcons.accounts, size: 64, color: cs.primary),
                ),
                const SizedBox(height: 32),
                Text(
                  'Welcome to Spendy',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Track spending, build savings and stay on top of bills.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _benefit(AppIcons.edit, 'Manual entry or bank SMS tracking'),
                _benefit(
                  Icons.auto_awesome_outlined,
                  'Voice entry, receipt scans and AI chat',
                ),
                _benefit(
                  Icons.lock_outline_rounded,
                  'Encrypted backups, when you choose',
                ),
                const SizedBox(height: 24),
                Text(
                  'Your records stay on this device unless you export or back them up.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
