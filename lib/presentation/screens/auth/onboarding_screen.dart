import 'package:flutter/material.dart';
import 'package:expencify/application/services/auth/auth_service.dart';
import 'package:expencify/presentation/screens/home/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:expencify/application/services/ai/ai_service.dart';
import 'package:expencify/application/services/ai/local_ai_model.dart';
import 'package:expencify/presentation/screens/setup/setup_required_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Welcome to Spendy',
      description:
          'Your privacy-first, offline-first smart finance manager. All your data stays on your device and is never shared with third-party servers.',
      icon: Icons.shield_rounded,
    ),
    OnboardingData(
      title: 'Smart Expense Logging',
      description:
          'Tap the \'+\' button on the home screen to log an expense. Short on time? Use the Camera icon to scan a physical receipt, and our on-device AI will automatically extract the amount and category!',
      icon: Icons.document_scanner_rounded,
    ),
    OnboardingData(
      title: 'Automate with SMS',
      description:
          'Tired of manual entry? Spendy can securely read bank transaction SMS alerts and log them automatically. \n\nIMPORTANT: You must add your Bank Account in the Accounts tab (and ensure the Bank Name matches your SMS) for the AI to recognize and track your messages!',
      icon: Icons.sms_rounded,
    ),
    OnboardingData(
      title: 'Security & Cloud Sync',
      description:
          'Keep prying eyes away by enabling App Lock. Want to switch phones safely? Backup your data directly to your own Google Drive using Military-Grade AES-256 End-to-End Encryption.',
      icon: Icons.cloud_sync_rounded,
    ),
    OnboardingData(
      title: 'Ready to Start?',
      description:
          'Let\'s set up your first account and take full control of your financial health.',
      icon: Icons.rocket_launch_rounded,
      isLastPage: true,
    ),
  ];

  void _goToHome() async {
    await _authService.setOnboarded();
    if (!mounted) return;

    // Check Requirements before opening Home
    final sms = await Permission.sms.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final ai = await AIService().modelExists(LocalAIModelType.qwenLite);
    final prefs = await SharedPreferences.getInstance();
    final legalAccepted = prefs.getBool('legal_terms_accepted') ?? false;
    final requirementsMet = sms && battery && ai && legalAccepted;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentPage != _pages.length - 1)
                    TextButton(
                      onPressed: _goToHome,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: theme.colorScheme.onBackground.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) =>
                    _buildPage(theme, _pages[index]),
              ),
            ),
            _buildBottomControls(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(ThemeData theme, OnboardingData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(data.icon, size: 100, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 48),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onBackground.withOpacity(0.6),
              height: 1.6,
            ),
          ),
          if (data.isLastPage) ...[
            const SizedBox(height: 64),
            ElevatedButton(
              onPressed: _goToHome,
              child: const Text('Get Started'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomControls(ThemeData theme) {
    bool isLastPage = _currentPage == _pages.length - 1;

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: List.generate(
              _pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 32 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _currentPage == index
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withOpacity(0.2),
                ),
              ),
            ),
          ),
          if (!isLastPage)
            IconButton.filled(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.fastOutSlowIn,
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
        ],
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;
  final bool isLastPage;

  OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
    this.isLastPage = false,
  });
}
