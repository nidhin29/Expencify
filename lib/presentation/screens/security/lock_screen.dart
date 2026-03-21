import 'package:flutter/material.dart';
import 'package:expencify/application/services/auth/auth_service.dart';
import 'package:expencify/application/services/security/security_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _security = SecurityService();
  final _auth = AuthService();
  String _pin = '';
  String? _expectedPin;
  String _error = '';
  bool _isLoading = true;
  bool _isBiometricPromptActive = false;

  @override
  void initState() {
    super.initState();
    _loadPinAndTryBiometrics();
  }

  Future<void> _loadPinAndTryBiometrics() async {
    final pin = await _security.getPin();
    if (mounted) {
      setState(() {
        _expectedPin = pin;
        _isLoading = false;
      });
    }
    final bioEnabled = await _security.isBiometricEnabled();
    if (bioEnabled) {
      _tryBiometrics();
    }
  }

  Future<void> _tryBiometrics() async {
    if (mounted) setState(() => _isBiometricPromptActive = true);
    final success = await _auth.authenticateWithBiometrics();
    if (success) {
      widget.onUnlocked();
    } else {
      if (mounted) setState(() => _isBiometricPromptActive = false);
    }
  }

  void _handleKey(String key) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += key;
      _error = '';
    });
    if (_pin.length == (_expectedPin?.length ?? 4)) {
      _verify();
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _verify() {
    if (_pin == _expectedPin) {
      widget.onUnlocked();
    } else {
      setState(() {
        _pin = '';
        _error = 'Incorrect PIN';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isBiometricPromptActive) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.fingerprint_rounded,
                size: 64,
                color: theme.colorScheme.primary.withOpacity(0.5),
              ),
              const SizedBox(height: 24),
              Text(
                'Waiting for biometric authentication...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'App Locked',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter PIN to continue',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 40),
                      if (_isLoading)
                        const SizedBox(height: 14) // Same height as dots
                      else
                        _buildPinDots(theme),
                      const SizedBox(height: 12),
                      if (_error.isNotEmpty)
                        Text(
                          _error,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      const Spacer(),
                      _buildKeypad(theme),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPinDots(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _expectedPin?.length ?? 4,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < _pin.length
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceVariant,
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var j = 1; j <= 3; j++)
                _buildKey((i * 3 + j).toString(), theme),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 96, height: 96), // Empty space for alignment
            _buildKey('0', theme),
            _buildKey('Del', theme, icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(String label, ThemeData theme, {IconData? icon}) {
    final isSpecial = label == 'Del';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: () {
          if (label == 'Del') {
            _backspace();
          } else {
            _handleKey(label);
          }
        },
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSpecial
                ? Colors.transparent
                : theme.colorScheme.surfaceVariant.withOpacity(0.3),
            border: isSpecial
                ? null
                : Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(0.05),
                  ),
          ),
          child: Center(
            child: icon != null
                ? Icon(
                    icon,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  )
                : Text(
                    label,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
