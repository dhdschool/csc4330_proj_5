import 'package:flutter/material.dart';

import '../api.dart';
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

/// Loading spinner / error with retry / content, for a [Future] that loads a list.
class AsyncList<T> extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.future,
    required this.onRetry,
    required this.emptyText,
    required this.itemBuilder,
  });

  final Future<List<T>> future;
  final VoidCallback onRetry;
  final String emptyText;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final err = snap.error;
          if (err is ApiException && err.isUnauthorized) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => showApiError(context, err));
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(err.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) return Center(child: Text(emptyText));
        return RefreshIndicator(
          onRefresh: () async => onRetry(),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => itemBuilder(context, items[i]),
          ),
        );
      },
    );
  }
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
