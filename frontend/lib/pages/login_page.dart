import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import 'courses_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.instance.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      _password.clear();
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CoursesPage()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.upload_file,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Gradescope Uploader',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text('Log in with your Gradescope email and password',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      // Browser autofill on Flutter web can break Backspace in the fields.
                      autofillHints: kIsWeb ? null : const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter your email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip:
                              _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      autofillHints:
                          kIsWeb ? null : const [AutofillHints.password],
                      onFieldSubmitted: (_) => _login(),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Enter your password' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Log in'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'School uses SSO? Set a Gradescope password first with '
                      '"Forgot password" on gradescope.com.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
