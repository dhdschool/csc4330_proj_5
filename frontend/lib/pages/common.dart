import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/ui.dart';
import 'login_page.dart';

/// Shows an error. If the session expired, sends the user back to login.
void showApiError(BuildContext context, Object error) {
  if (error is ApiException && error.isUnauthorized) {
    signOut(context, message: error.message);
    return;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));
}

Future<void> signOut(BuildContext context, {String? message}) async {
  await Api.instance.logout();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (_) => false,
  );
  if (message != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Log out',
      icon: const Icon(Icons.logout),
      onPressed: () => signOut(context),
    );
  }
}

/// Loading skeleton / error with retry / empty message / content, for a
/// [Future] that loads a list.
///
/// [builder] turns the items into the rows to show (cards, section labels);
/// each row slides in just after the one above it. Pull down to reload.
class AsyncList<T> extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.future,
    required this.onRetry,
    required this.emptyText,
    this.emptyIcon = Icons.inbox_outlined,
    required this.builder,
  });

  final Future<List<T>> future;
  final VoidCallback onRetry;
  final String emptyText;
  final IconData emptyIcon;
  final List<Widget> Function(BuildContext, List<T>) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoadingSkeleton();
        }
        if (snap.hasError) {
          final err = snap.error;
          if (err is ApiException && err.isUnauthorized) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => showApiError(context, err));
          }
          return _StatusMessage(
            icon: Icons.cloud_off_rounded,
            text: err.toString(),
            error: true,
            action: FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) return _StatusMessage(icon: emptyIcon, text: emptyText);
        final rows = builder(context, items);
        return RefreshIndicator(
          onRefresh: () async => onRetry(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: Entrance(index: i, child: row),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Gently pulsing placeholder cards while a list loads.
class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton();

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bar(double widthFactor) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: _pulse.drive(Tween(begin: 0.4, end: 1.0)),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              for (var i = 0; i < 6; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(i.isEven ? 0.7 : 0.55),
                            const SizedBox(height: 8),
                            bar(0.35),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big icon with a message under it, for empty lists and errors.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage(
      {required this.icon, required this.text, this.error = false, this.action});

  final IconData icon;
  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Entrance(
              index: 0,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: error ? scheme.errorContainer : scheme.secondaryContainer,
                ),
                child: Icon(icon,
                    size: 36,
                    color: error
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: 16),
            Entrance(
              index: 1,
              child: Text(text,
                  textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              Entrance(index: 2, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Narrow, centered column so pages look right in a wide browser window.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: child,
      ),
    );
  }
}
