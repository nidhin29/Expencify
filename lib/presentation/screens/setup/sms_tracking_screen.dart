import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../application/services/notifications/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../application/services/sms/sms_monitor_service.dart';
import '../../../application/services/sms/sms_tracking_preference.dart';
import '../../../application/blocs/account/account_bloc.dart';
import '../../../application/blocs/account/account_event.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/repositories/account_repository.dart';
import '../../widgets/account_editor.dart';

class SmsTrackingScreen extends StatefulWidget {
  const SmsTrackingScreen({super.key});
  @override
  State<SmsTrackingScreen> createState() => _SmsTrackingScreenState();
}

class _SmsTrackingScreenState extends State<SmsTrackingScreen>
    with WidgetsBindingObserver {
  bool _permission = false, _busy = false, _permanent = false;
  List<Account> _accounts = [];
  String? _error;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ready => _permission && _accounts.any(AccountEditor.hasSmsDetails);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final permission = _supported && await Permission.sms.isGranted;
    if (!mounted) return;
    final accounts = await context.read<AccountRepository>().getAll();
    if (mounted) {
      setState(() {
        _permission = permission;
        _accounts = accounts;
      });
    }
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_permanent) await openAppSettings();
      final status = _permanent
          ? await Permission.sms.status
          : await Permission.sms.request();
      if (mounted) {
        setState(() {
          _permission = status.isGranted;
          _permanent = status.isPermanentlyDenied;
          _error = status.isGranted
              ? null
              : 'SMS access is off. You can keep using manual tracking.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not enable SMS access. Try again or use manual tracking.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBank({Account? existing}) async {
    final repository = context.read<AccountRepository>();
    final accountBloc = context.read<AccountBloc>();
    final account = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AccountEditor(
        allowCash: false,
        existing: existing,
        onSubmit: (account) async {
          try {
            await repository.save(account);
            accountBloc.add(LoadAccounts());
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
    if (account != null && mounted) await _load();
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      if (!await Permission.sms.isGranted) {
        await _load();
        return;
      }
      await NotificationService().requestPermission();
      await SmsTrackingPreference.setEnabled(true);
      await SmsMonitorService().startBackgroundListening();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      await SmsTrackingPreference.setEnabled(false);
      if (mounted) {
        setState(
          () => _error = 'Could not start SMS tracking. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SMS tracking')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Track bank transactions automatically',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Bank SMS are matched on your device. Only your bank name and last four account digits are needed.',
          ),
          const SizedBox(height: 24),
          if (!_supported)
            const Text(
              'SMS tracking is available on Android. Manual tracking is available here.',
            )
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _permission ? AppIcons.success : Icons.sms_outlined,
              ),
              title: const Text('SMS access'),
              subtitle: Text(
                _permission
                    ? 'Allowed'
                    : 'Read incoming bank transaction alerts',
              ),
            ),
            if (!_permission)
              FilledButton(
                onPressed: _busy ? null : _request,
                child: Text(
                  _permanent ? 'Open app settings' : 'Allow SMS access',
                ),
              ),
            if (_permission) ...[
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_ready ? AppIcons.success : AppIcons.bank),
                title: const Text('Bank details'),
                subtitle: Text(
                  _ready
                      ? 'Ready to match transactions'
                      : 'Add your bank and last four account digits',
                ),
              ),
              ..._accounts
                  .where(
                    (account) =>
                        !AccountEditor.isCash(account) &&
                        !AccountEditor.hasSmsDetails(account),
                  )
                  .map(
                    (account) => ListTile(
                      title: Text(account.name),
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _addBank(existing: account),
                        child: const Text('Complete details'),
                      ),
                    ),
                  ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _addBank(),
                icon: const Icon(AppIcons.add),
                label: Text(_ready ? 'Add another bank' : 'Add bank account'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _ready && !_busy ? _enable : null,
                child: const Text('Enable SMS tracking'),
              ),
            ],
          ],
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await SmsMonitorService().stopBackgroundListening();
                    if (context.mounted) Navigator.pop(context, false);
                  },
            child: const Text('Use manually'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
