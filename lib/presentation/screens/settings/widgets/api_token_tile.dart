import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// API Token 設定項目
class ApiTokenTile extends ConsumerStatefulWidget {
  const ApiTokenTile({super.key});

  @override
  ConsumerState<ApiTokenTile> createState() => _ApiTokenTileState();
}

class _ApiTokenTileState extends ConsumerState<ApiTokenTile> {
  bool _hasToken = false;
  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _loadTokenStatus();
  }

  Future<void> _loadTokenStatus() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final hasToken = await settingsRepo.hasFinMindToken();
    if (mounted) {
      setState(() {
        _hasToken = hasToken;
        _isLoading = false;
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final connectionService = ref.read(apiConnectionServiceProvider);
    final token = await settingsRepo.getFinMindToken();

    final result = await connectionService.testFinMindConnection(token);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = result.success;
        _testResult = result.success
            ? 'settings.apiTestSuccess'.tr(
                namedArgs: {'count': result.stockCount.toString()},
              )
            : 'settings.apiTestFailed'.tr(
                namedArgs: {'error': result.errorMessage ?? 'empty.error'.tr()},
              );
      });
    }
  }

  void _showTokenDialog() {
    final controller = TextEditingController();
    final theme = Theme.of(context);

    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('settings.apiToken'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'settings.apiTokenHint'.tr(),
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: DesignTokens.spacing8),
              // 用 TextButton 確保命中區 ≥ 44dp（HIG/WCAG），裸 InkWell
              // 的 line height ~12dp 太小。
              TextButton(
                onPressed: _openRegisterUrl,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacing4,
                    vertical: DesignTokens.spacing8,
                  ),
                  minimumSize: const Size(0, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(
                  'settings.apiRegister'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (_hasToken)
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _clearToken();
                },
                child: Text(
                  'common.delete'.tr(),
                  style: const TextStyle(color: AppTheme.errorColor),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () async {
                      final token = controller.text.trim();
                      Navigator.pop(dialogContext);
                      await _saveToken(token);
                    },
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    ).then((_) {
      controller.dispose();
    });
  }

  Future<void> _saveToken(String token) async {
    if (!FinMindClient.isValidTokenFormat(token)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('settings.apiTokenInvalid'.tr()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setFinMindToken(token);

    ref.invalidate(finMindClientProvider);

    if (mounted) {
      setState(() {
        _hasToken = true;
        _testResult = null;
        _testSuccess = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('settings.apiTokenSaved'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearToken() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.clearFinMindToken();

    ref.invalidate(finMindClientProvider);

    if (mounted) {
      setState(() {
        _hasToken = false;
        _testResult = null;
        _testSuccess = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('settings.apiTokenCleared'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openRegisterUrl() async {
    final url = Uri.parse(ApiEndpoints.finmindWebsite);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) _showLinkError();
      }
    } catch (_) {
      if (mounted) _showLinkError();
    }
  }

  void _showLinkError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('empty.error'.tr()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return ListTile(
        leading: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('common.loading'.tr()),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(
            _hasToken ? Icons.key_rounded : Icons.key_off_rounded,
            color: _hasToken
                ? DesignTokens.successColor(theme)
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text('settings.apiToken'.tr()),
          subtitle: Text(
            _hasToken
                ? 'settings.apiTokenSet'.tr()
                : 'settings.apiTokenNotSet'.tr(),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showTokenDialog,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacing16,
            vertical: DesignTokens.spacing8,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(
                    _isTesting
                        ? 'settings.apiTesting'.tr()
                        : 'settings.apiTestConnection'.tr(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_testResult != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing16,
              vertical: DesignTokens.spacing4,
            ),
            child: Row(
              children: [
                Icon(
                  _testSuccess == true ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: _testSuccess == true
                      ? DesignTokens.successColor(theme)
                      : AppTheme.errorColor,
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Expanded(
                  child: Text(
                    _testResult!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _testSuccess == true
                          ? DesignTokens.successColor(theme)
                          : AppTheme.errorColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: DesignTokens.spacing8),
      ],
    );
  }
}
