import 'dart:async';
import 'package:flutter/material.dart';

/// Tabs return to the dashboard; leaving the dashboard requires a second Back.
class HomeBackHandler extends StatefulWidget {
  final int selectedIndex;
  final VoidCallback onReturnHome;
  final Widget child;
  const HomeBackHandler({
    super.key,
    required this.selectedIndex,
    required this.onReturnHome,
    required this.child,
  });
  @override
  State<HomeBackHandler> createState() => _HomeBackHandlerState();
}

class _HomeBackHandlerState extends State<HomeBackHandler>
    with WidgetsBindingObserver {
  bool _exitArmed = false;
  Timer? _timer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _prompt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(HomeBackHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _timer?.cancel();
      _exitArmed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dismissPrompt();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _exitArmed) {
      _timer?.cancel();
      setState(() => _exitArmed = false);
      _dismissPrompt();
    }
  }

  void _dismissPrompt() {
    final prompt = _prompt;
    _prompt = null;
    prompt?.close();
  }

  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    if (widget.selectedIndex != 0) {
      widget.onReturnHome();
      return;
    }
    setState(() => _exitArmed = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    _prompt = messenger.showSnackBar(
      const SnackBar(
        persist: false,
        duration: Duration(seconds: 2),
        content: Text('Press back again to exit'),
      ),
    );
    final prompt = _prompt;
    prompt?.closed.then((_) {
      if (identical(_prompt, prompt)) _prompt = null;
    });
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _exitArmed = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: widget.selectedIndex == 0 && _exitArmed,
    onPopInvokedWithResult: _onBack,
    child: widget.child,
  );
}
