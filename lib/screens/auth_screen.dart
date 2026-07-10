import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _serverCtrl = TextEditingController(text: ApiService.baseUrl);
  bool _isLogin = true;
  bool _showServer = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    auth.clearError();
    if (!_formKey.currentState!.validate()) return;
    if (_serverCtrl.text.trim().isNotEmpty) {
      await ApiService.setBaseUrl(_serverCtrl.text.trim());
    }
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (_isLogin) {
      await auth.login(email, password);
    } else {
      await auth.signup(email, password, name: _nameCtrl.text);
    }
  }

  void _toggleMode() {
    setState(() => _isLogin = !_isLogin);
    context.read<AuthProvider>().clearError();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final auth = context.watch<AuthProvider>();

    return FScaffold(
      childPad: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand
                  Icon(Icons.auto_awesome, size: 40, color: colors.primary),
                  const SizedBox(height: 12),
                  Text('Nexus AI',
                      textAlign: TextAlign.center,
                      style: typography.display.xl2
                          .copyWith(fontWeight: FontWeight.bold, color: colors.foreground)),
                  const SizedBox(height: 4),
                  Text(_isLogin ? 'Welcome back' : 'Create your account',
                      textAlign: TextAlign.center,
                      style: typography.body.sm.copyWith(color: colors.mutedForeground)),
                  const SizedBox(height: 28),

                  if (!_isLogin) ...[
                    FTextFormField(
                      control: FTextFieldControl.managed(controller: _nameCtrl),
                      label: const Text('Name (optional)'),
                      hint: 'Your name',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                  ],

                  FTextFormField.email(
                    control: FTextFieldControl.managed(controller: _emailCtrl),
                    label: const Text('Email'),
                    hint: 'you@example.com',
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Email is required';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  FTextFormField.password(
                    control: FTextFieldControl.managed(controller: _passwordCtrl),
                    label: const Text('Password'),
                    hint: '••••••••',
                    textInputAction: TextInputAction.done,
                    onSubmit: (_) => _submit(),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Password is required';
                      if ((v ?? '').length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),

                  if (auth.error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.destructive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: colors.destructive.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: colors.destructive),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(auth.error!,
                                style: typography.body.sm
                                    .copyWith(color: colors.destructive)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),
                  FButton(
                    onPress: auth.busy ? null : _submit,
                    child: auth.busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: colors.primaryForeground))
                        : Text(_isLogin ? 'Log in' : 'Sign up'),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                          _isLogin
                              ? "Don't have an account?"
                              : 'Already have an account?',
                          style: typography.body.sm
                              .copyWith(color: colors.mutedForeground)),
                      FButton(
                        variant: FButtonVariant.ghost,
                        onPress: auth.busy ? null : _toggleMode,
                        child: Text(_isLogin ? 'Sign up' : 'Log in'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Backend URL — collapsible so it stays out of the way, but is
                  // reachable before login (essential on Android/emulator).
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: () => setState(() => _showServer = !_showServer),
                    prefix: Icon(Icons.dns_outlined,
                        size: 16, color: colors.mutedForeground),
                    suffix: Icon(
                        _showServer ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: colors.mutedForeground),
                    child: Text('Server settings',
                        style: typography.body.sm
                            .copyWith(color: colors.mutedForeground)),
                  ),
                  if (_showServer) ...[
                    const SizedBox(height: 8),
                    FTextFormField(
                      control: FTextFieldControl.managed(controller: _serverCtrl),
                      label: const Text('Backend URL'),
                      hint: 'http://10.0.2.2:8080',
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Emulator: http://10.0.2.2:8080  ·  device: http://<your-PC-IP>:8080',
                      style: typography.body.xs.copyWith(color: colors.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
