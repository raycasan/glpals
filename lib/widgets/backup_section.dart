import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../backup_service.dart';
import '../theme.dart';
import 'common.dart';

/// Google Drive backup: sign in, back up, restore, and say plainly what
/// happened. Shared by the settings page and anywhere else that needs it.
class BackupSection extends StatelessWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final svc = BackupService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final children = <Widget>[];
        if (!svc.configured) {
          children.addAll([
            Text(
              'Paste the Web application client ID from your Google Cloud '
              'project. It ends in .apps.googleusercontent.com. On iPhone the '
              'app also needs an iOS client ID built into it, which cannot be '
              'pasted here.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 14),
            const _ClientIdField(),
          ]);
        } else if (!svc.hasAccount) {
          children.addAll([
            Text(svc.linkMessage,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: svc.busy ? null : svc.signIn,
              icon: svc.isRunning(BackupTask.signIn)
                  ? const _Spinner()
                  : const Icon(Icons.cloud_outlined),
              label: Text(svc.isRunning(BackupTask.signIn)
                  ? 'Opening Google…'
                  : 'Sign in with Google'),
            ),
          ]);
        } else if (!svc.signedIn) {
          // An account is remembered but the session is asleep. Say who it is
          // and what will fix it, rather than pretending nobody signed in.
          children.addAll([
            _AccountRow(svc: svc),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (svc.link == GoogleLink.restoring
                        ? Palette.sky
                        : Palette.peach)
                    .withValues(alpha: .16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  if (svc.link == GoogleLink.restoring)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  else
                    const Icon(Icons.link_off_rounded,
                        size: 19, color: Palette.peach),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(svc.linkMessage,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            if (svc.link != GoogleLink.restoring) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: svc.busy ? null : svc.signIn,
                icon: svc.isRunning(BackupTask.signIn)
                    ? const _Spinner()
                    : const Icon(Icons.link_rounded),
                label: Text(svc.isRunning(BackupTask.signIn)
                    ? 'Reconnecting…'
                    : 'Reconnect'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: svc.busy ? null : svc.signOut,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Use a different account'),
              ),
            ],
          ]);
        } else {
          children.addAll([
            _AccountRow(svc: svc, showSignOut: true),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Back up automatically',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              subtitle: Text('A few seconds after each save',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
              value: svc.autoBackup,
              onChanged: svc.busy ? null : svc.setAutoBackup,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: svc.busy ? null : () => _backup(context),
                    // The spinner belongs to the button that was pressed, so
                    // it tracks the running task rather than plain busy.
                    icon: svc.isRunning(BackupTask.backup)
                        ? const _Spinner()
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(svc.isRunning(BackupTask.backup)
                        ? 'Backing up…'
                        : 'Back up now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: svc.busy ? null : () => _restore(context),
                    icon: svc.isRunning(BackupTask.restore)
                        ? const _Spinner()
                        : const Icon(Icons.cloud_download_outlined),
                    label: Text(svc.isRunning(BackupTask.restore)
                        ? 'Restoring…'
                        : 'Restore'),
                  ),
                ),
              ],
            ),
          ]);
        }
        if (svc.lastMessage != null) {
          children.addAll([
            const SizedBox(height: 14),
            _Banner(
                text: svc.lastMessage!,
                color: Palette.mint,
                icon: Icons.check_circle_rounded),
          ]);
        }
        if (svc.lastError != null) {
          children.addAll([
            const SizedBox(height: 14),
            _Banner(
                text: svc.lastError!,
                color: Palette.berry,
                icon: Icons.error_outline_rounded),
          ]);
        }
        children.addAll([
          const SizedBox(height: 16),
          Text(
            'Meal photos stay on the phone. Everything else, including your '
            'API key, goes to a private folder only this app can read.',
            style: TextStyle(
                fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
          ),
        ]);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children);
      },
    );
  }

  Future<void> _backup(BuildContext context) async {
    await BackupService.instance.backupNow();
  }

  Future<void> _restore(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
            'This replaces everything on this phone with your cloud backup. '
            'Meal photos are not included.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await BackupService.instance.restore();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Lets the Web client ID be pasted on the phone, so switching backup on does
/// not need a rebuild.
class _ClientIdField extends StatefulWidget {
  const _ClientIdField();

  @override
  State<_ClientIdField> createState() => _ClientIdFieldState();
}

class _ClientIdFieldState extends State<_ClientIdField> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await BackupService.instance.saveClientId(_ctrl.text);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Client ID saved. Sign in with Google below.'
          : 'That does not look like a client ID.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _ctrl,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Web client ID',
            hintText: '1234-abcd.apps.googleusercontent.com',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Save client ID'),
        ),
      ],
    );
  }
}

/// Who is connected, and when the last backup ran. Shared by the connected
/// and reconnecting states so the card does not jump around.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.svc, this.showSignOut = false});
  final BackupService svc;
  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = svc.lastBackup;
    final photo = svc.accountPhoto;
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: scheme.primary.withValues(alpha: .15),
          backgroundImage: photo != null ? NetworkImage(photo) : null,
          child: photo == null ? const Icon(Icons.person_rounded) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(svc.accountLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              Text(
                last == null
                    ? 'No backup yet'
                    : 'Last backup ${relativeDay(last)} · ${DateFormat('h:mm a').format(last)}',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (showSignOut)
          TextButton(
              onPressed: svc.busy ? null : svc.signOut,
              child: const Text('Sign out')),
      ],
    );
  }
}

/// Button-sized progress indicator.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
