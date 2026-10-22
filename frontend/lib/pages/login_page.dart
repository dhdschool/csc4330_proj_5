import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../widgets/ui.dart';
import 'courses_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _fields = Listenable.merge([_email, _password]);
  late final _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _reject() {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return _reject();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.instance.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      _password.clear();
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => const CoursesPage(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
                scale: curved.drive(Tween(begin: 0.96, end: 1.0)), child: child),
          );
        },
      ));
    } catch (e) {
      setState(() => _error = e.toString());
      _reject();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.primaryContainer.withValues(alpha: 0.6), scheme.surface],
            stops: const [0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Entrance(index: 0, child: Center(child: _Logo())),
                        const SizedBox(height: 20),
                        Entrance(
                          index: 1,
                          child: Text('Gradescope Uploader',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 6),
                        Entrance(
                          index: 2,
                          child: Text(
                              'Log in with your Gradescope email and password',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                        const SizedBox(height: 28),
                        Entrance(
                          index: 3,
                          child: ShakeTransition(
                            animation: _shake,
                            child: _card(context),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Entrance(
                          index: 4,
                          child: ListenableBuilder(
                            listenable: _fields,
                            builder: (context, _) => PillButton(
                              label: 'Log in',
                              icon: Icons.login_rounded,
                              busy: _loading,
                              busyLabel: 'Logging in…',
                              glow: _email.text.contains('@') &&
                                  _password.text.isNotEmpty,
                              onPressed: _login,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Entrance(
                          index: 5,
                          child: Text(
                            'School uses SSO? Set a Gradescope password first with '
                            '"Forgot password" on gradescope.com.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FocusGlow(
            child: TextFormField(
              controller: _email,
              decoration: softInputDecoration(context,
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.alternate_email_rounded)),
              keyboardType: TextInputType.emailAddress,
              // Browser autofill on Flutter web can break Backspace in the fields.
              autofillHints: kIsWeb ? null : const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              onTapOutside: unfocusOnTapOutside,
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Enter your email' : null,
            ),
          ),
          const SizedBox(height: 12),
          FocusGlow(
            child: TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: softInputDecoration(
                context,
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: Tween(begin: -0.25, end: 0.0).animate(anim),
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: Icon(
                      _showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      key: ValueKey(_showPassword),
                    ),
                  ),
                ),
              ),
              autofillHints: kIsWeb ? null : const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onTapOutside: unfocusOnTapOutside,
              onFieldSubmitted: (_) => _login(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ErrorBanner(message: _error!),
                  ),
          ),
        ],
      ),
    );
  }
}

/// App icon in a gradient circle that springs in.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(Icons.upload_file_rounded, size: 38, color: scheme.onPrimary),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
