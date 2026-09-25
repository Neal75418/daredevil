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

  Future<void> _showTokenDialog() async {
    HapticFeedback.lightImpact();
    final result = await showDialog<_TokenDialogResult>(
      context: context,
      builder: (_) => _ApiTokenDialog(
        hasToken: _hasToken,
        onOpenRegister: _openRegisterUrl,
      ),
    );
    switch (result) {
      case _SaveToken(:final token):
        await _saveToken(token);
      case _ClearToken():
        await _clearToken();
      case null:
        break;
    }
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

    // await 前先取好：寫入 keychain 期間使用者離開設定頁，之後的 ref 會失效
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final tokenNotifier = ref.read(finMindTokenProvider.notifier);
    await settingsRepo.setFinMindToken(token);

    // client watch 這個 provider，會自動以新 token 重建
    tokenNotifier.set(token);

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
    final tokenNotifier = ref.read(finMindTokenProvider.notifier);
    await settingsRepo.clearFinMindToken();

    tokenNotifier.set(null);

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

/// Token 對話框的結果
sealed class _TokenDialogResult {}

final class _SaveToken extends _TokenDialogResult {
  _SaveToken(this.token);
  final String token;
}

final class _ClearToken extends _TokenDialogResult {}

/// Token 輸入對話框
///
/// 🚨 controller 必須由對話框自己持有、在 [State.dispose] 釋放：原本在
/// `showDialog(...).then` 裡 dispose，但 future 在 pop 當下就完成，關閉動畫
/// 期間 TextField 仍會重建，用到已釋放的 controller（debug 下每次存／刪
/// token 都丟 assertion）。State.dispose 要等 route 真正移除才會呼叫。
class _ApiTokenDialog extends StatefulWidget {
  const _ApiTokenDialog({required this.hasToken, required this.onOpenRegister});

  final bool hasToken;
  final VoidCallback onOpenRegister;

  @override
  State<_ApiTokenDialog> createState() => _ApiTokenDialogState();
}

class _ApiTokenDialogState extends State<_ApiTokenDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final token = _controller.text.trim();

    return AlertDialog(
      title: Text('settings.apiToken'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'settings.apiTokenHint'.tr(),
              border: const OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: DesignTokens.spacing8),
          // 用 TextButton 確保命中區 ≥ 44dp（HIG/WCAG），裸 InkWell
          // 的 line height ~12dp 太小。
          TextButton(
            onPressed: widget.onOpenRegister,
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
        if (widget.hasToken)
          TextButton(
            onPressed: () => Navigator.pop(context, _ClearToken()),
            child: Text(
              'common.delete'.tr(),
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: token.isEmpty
              ? null
              : () => Navigator.pop(context, _SaveToken(token)),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
