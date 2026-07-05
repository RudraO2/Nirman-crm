import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
import '../utils/auth_validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;
  bool _passwordVisible = false;

  // Light ink used on the dark evergreen panel.
  static const _ivoryText = Color(0xFFF2EEE2);

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(authRepositoryProvider).login(
            username: username,
            password: password,
          );
      if (!mounted) return;
      if (result.mustChangePassword) {
        // Persist flag before navigating so the router guard survives app restarts (AC-7).
        // JWT app_metadata also carries must_change_password=true as a fallback (survives reinstall).
        final userId = ref.read(authRepositoryProvider).currentSession?.user.id;
        if (userId != null) {
          const storage = FlutterSecureStorage();
          await storage.write(key: mustChangePasswordKey(userId), value: 'true');
        }
        if (!mounted) return;
        context.go('/password-change');
      } else {
        context.go('/home');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = mapLoginError(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.evergreen,
              AppColors.evergreenDeep,
              Color(0xFF0A1912),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brass logo mark.
                  Container(
                    width: 58, height: 58,
                    decoration: BoxDecoration(
                      color: AppColors.brass,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'N',
                      style: GoogleFonts.fraunces(
                        fontSize: 27,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        color: AppColors.evergreenDeep,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Nirman CRM',
                    style: GoogleFonts.fraunces(
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                      color: _ivoryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to your account',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: const Color(0xFFE9E4D6).withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 30),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFF3D9D5), fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _fieldLabel('Username'),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _usernameController,
                    decoration: _darkInput('ravi.kumar'),
                    style: const TextStyle(color: _ivoryText, fontSize: 15),
                    cursorColor: AppColors.brassBright,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_loading,
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('Password'),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_passwordVisible,
                    decoration: _darkInput('••••••••').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisible ? Icons.visibility_off : Icons.visibility,
                          color: const Color(0xFFE9E4D6).withValues(alpha: 0.5),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                      ),
                    ),
                    style: const TextStyle(color: _ivoryText, fontSize: 15),
                    cursorColor: AppColors.brassBright,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _loading ? null : _submit(),
                    enabled: !_loading,
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brass,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.brass.withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Log In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: const Color(0xFFE9E4D6).withValues(alpha: 0.5),
        ),
      );

  InputDecoration _darkInput(String hint) {
    OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: const Color(0xFFE9E4D6).withValues(alpha: 0.3), fontSize: 15),
      filled: true,
      fillColor: const Color(0xFFE9E4D6).withValues(alpha: 0.07),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      border: border(const Color(0xFFE9E4D6).withValues(alpha: 0.16)),
      enabledBorder: border(const Color(0xFFE9E4D6).withValues(alpha: 0.16)),
      focusedBorder: border(AppColors.brassBright),
      disabledBorder: border(const Color(0xFFE9E4D6).withValues(alpha: 0.10)),
    );
  }
}
