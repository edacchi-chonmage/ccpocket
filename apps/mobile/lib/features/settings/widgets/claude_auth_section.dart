import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';

class ClaudeAuthSection extends StatefulWidget {
  final BridgeService bridgeService;
  final String? activeMachineName;

  const ClaudeAuthSection({
    super.key,
    required this.bridgeService,
    this.activeMachineName,
  });

  @override
  State<ClaudeAuthSection> createState() => _ClaudeAuthSectionState();
}

class _ClaudeAuthSectionState extends State<ClaudeAuthSection> {
  StreamSubscription<ServerMessage>? _messageSub;
  StreamSubscription<BridgeConnectionState>? _connectionSub;
  final _codeController = TextEditingController();
  ClaudeAuthStatusMessage? _status;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() {
      if (mounted) setState(() {});
    });
    _messageSub = widget.bridgeService.messages.listen((msg) {
      if (msg is! ClaudeAuthStatusMessage) return;
      if (!mounted) return;
      setState(() {
        _status = msg;
      });
    });
    _connectionSub = widget.bridgeService.connectionStatus.listen((state) {
      if (state == BridgeConnectionState.connected) {
        _requestStatus();
      }
    });
    _requestStatus();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _connectionSub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _requestStatus() {
    widget.bridgeService.send(ClientMessage.getClaudeAuthStatus());
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _status;
    final title = switch (status?.state) {
      'success' when status?.authenticated == true => 'Authenticated',
      'waiting_code' => 'Waiting for verification code',
      'authorizing' => 'Completing authentication',
      'starting' => 'Starting login',
      'cancelled' => 'Login cancelled',
      'error' => 'Authentication failed',
      _ when status?.authenticated == true => 'Authenticated',
      _ => 'Login required',
    };

    final subtitle =
        status?.message ??
        (widget.bridgeService.isConnected
            ? 'Authenticate Claude Code on the connected Bridge machine.'
            : 'Connect to a Bridge machine to manage Claude Code authentication.');

    final isBusy = status?.loginInProgress == true;
    final canSubmitCode =
        status?.state == 'waiting_code' || status?.state == 'authorizing';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Claude Authentication',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: status?.authenticated == true
                              ? Colors.green.shade700
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.activeMachineName != null)
              Text(
                'Machine: ${widget.activeMachineName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (widget.activeMachineName != null) const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if ((status?.loginUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Login URL', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    SelectableText(
                      status!.loginUrl!,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _openUrl(status.loginUrl!),
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open Login URL'),
                    ),
                  ],
                ),
              ),
            ],
            if ((status?.prompt ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                status!.prompt!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              enabled: widget.bridgeService.isConnected && canSubmitCode,
              decoration: const InputDecoration(
                labelText: 'Verification code',
                hintText: 'Paste the code shown after browser auth',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: !widget.bridgeService.isConnected || isBusy
                      ? null
                      : () {
                          widget.bridgeService.send(
                            ClientMessage.startClaudeAuthLogin(),
                          );
                        },
                  child: const Text('Authenticate'),
                ),
                OutlinedButton(
                  onPressed: !widget.bridgeService.isConnected
                      ? null
                      : _requestStatus,
                  child: const Text('Check Again'),
                ),
                OutlinedButton(
                  onPressed:
                      !widget.bridgeService.isConnected ||
                          !canSubmitCode ||
                          _codeController.text.trim().isEmpty
                      ? null
                      : () {
                          widget.bridgeService.send(
                            ClientMessage.submitClaudeAuthCode(
                              _codeController.text.trim(),
                            ),
                          );
                        },
                  child: const Text('Submit Code'),
                ),
                TextButton(
                  onPressed: isBusy
                      ? () {
                          widget.bridgeService.send(
                            ClientMessage.cancelClaudeAuthLogin(),
                          );
                        }
                      : null,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (!widget.bridgeService.isConnected) ...[
              const SizedBox(height: 8),
              Text(
                'Bridge is not connected.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
