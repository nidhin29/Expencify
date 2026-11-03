import 'package:flutter/material.dart';
import '../../application/services/security/security_service.dart';
import '../../application/services/auth/auth_service.dart';
import '../screens/security/lock_screen.dart';
import 'spendy_splash_visual.dart';

/// Keeps hidden routes alive, but removes their paint, focus and semantics.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final SecurityService? security;
  final AuthService? auth;
  const AppLockGate({super.key, required this.child, this.security, this.auth});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late final _security = widget.security ?? SecurityService();
  final _lockNavigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _security,
    builder: (context, _) {
      final covered = _security.isPrivacyCovered;
      final locked = _security.isLocked;
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: covered || locked,
            child: Offstage(
              offstage: covered || locked,
              child: TickerMode(
                enabled: !covered && !locked,
                child: widget.child,
              ),
            ),
          ),
          if (locked)
            ExcludeFocus(
              excluding: covered,
              child: Offstage(
                offstage: covered,
                child: HeroControllerScope.none(
                  child: Navigator(
                    key: _lockNavigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => LockScreen(
                        securityService: _security,
                        authService: widget.auth,
                        onUnlocked: _security.unlock,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (covered)
            const AnnotatedRegion(
              value: appLockOverlayStyle,
              child: Material(
                color: Color(0xFF100A1E),
                child: Center(child: SpendySplashVisual(progress: 1)),
              ),
            ),
        ],
      );
    },
  );
}
