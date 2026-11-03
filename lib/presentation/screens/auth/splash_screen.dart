import 'package:flutter/services.dart';
import 'dart:async';
import '../../widgets/spendy_splash_visual.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../application/services/auth/auth_service.dart';
import '../../../application/services/security/security_service.dart';
import '../home/home_screen.dart';
import '../setup/setup_required_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.ready, this.firstFrame});

  /// Keeps the original splash visible until database and security are ready.
  final Future<void>? ready;

  /// Begin the animation after the launch frame is rasterized, not behind the
  /// previous Android surface while a cold engine is still starting.
  final Future<void>? firstFrame;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _loadingTimer;
  bool _showLoading = false;
  bool _animationStarted = false;
  final _animationFinished = Completer<void>();
  String _loadingStage = 'Opening your secure data…';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToNext();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (!_animationStarted) _startLoadingTimer();
      _controller.stop();
      _controller.value = 1;
      _animationStarted = true;
      if (!_animationFinished.isCompleted) _animationFinished.complete();
    } else if (!_animationStarted) {
      _animationStarted = true;
      unawaited(_playVisibleAnimation());
    }
  }

  Future<void> _playVisibleAnimation() async {
    if (widget.firstFrame != null) await widget.firstFrame;
    if (!mounted || _animationFinished.isCompleted) return;
    _startLoadingTimer();
    try {
      await _controller.forward().orCancel;
      if (!_animationFinished.isCompleted) _animationFinished.complete();
    } on TickerCanceled {
      // Navigation/disposal cancels only this visual; it never restarts startup.
    }
  }

  void _startLoadingTimer() {
    _loadingTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showLoading = true);
    });
  }

  Future<void> _navigateToNext() async {
    await widget.ready;
    await _animationFinished.future;
    if (!mounted) return;
    setState(() => _loadingStage = 'Checking your setup…');
    // Initialization runs during the animation; no network check delays exit.

    final authService = AuthService();
    final bool onboarded = await authService.isOnboarded();

    if (!mounted) return;

    Widget nextScreen;
    if (!onboarded) {
      nextScreen = const OnboardingScreen();
    } else {
      // Check Requirements before opening Home
      final prefs = await SharedPreferences.getInstance();
      final legalAccepted = prefs.getBool('legal_terms_accepted') ?? false;
      final requirementsMet = legalAccepted;

      if (!mounted) return;

      if (!requirementsMet) {
        nextScreen = SetupRequiredScreen(
          onComplete: (ctx) {
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          },
        );
      } else {
        nextScreen = const HomeScreen();
      }
    }

    final security = SecurityService();
    security.setSplashActive(false);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    if (!_animationFinished.isCompleted) _animationFinished.complete();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF100A1E),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.2),
                  radius: 1.2,
                  colors: [Color(0xFF281447), Color(0xFF100A1E)],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (_, _) =>
                              SpendySplashVisual(progress: _controller.value),
                        ),
                      ),
                    ),
                    if (_showLoading)
                      Positioned(
                        left: 32,
                        right: 32,
                        bottom: 40,
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: reducedMotion
                                    ? const Icon(
                                        Icons.hourglass_empty_rounded,
                                        size: 16,
                                        color: Color(0xFFC4B5FD),
                                      )
                                    : const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFC4B5FD),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  _loadingStage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD9CFEA),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                key: const ValueKey('splash-status-strip'),
                height: MediaQuery.paddingOf(context).top,
                decoration: const BoxDecoration(
                  color: Color(0xFF0B0714),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF372449), width: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
