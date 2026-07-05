import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
import '../utils/auth_validators.dart';

class PasswordChangeScreen extends ConsumerStatefulWidget {
  /// [isForced] = true when called from must_change_password flow.
  /// When true, back navigation is blocked until the change succeeds.
  final bool isForced;

  const PasswordChangeScreen({super.key, this.isForced = true});

  @override
  ConsumerState<PasswordChangeScreen> createState() =>
      _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends ConsumerState<PasswordChangeScreen> {
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _currentPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final localError = validateNewPassword(
      newPassword: _newPwController.text,
      confirm: _confirmPwController.text,
    );
    if (localError != null) {
      setState(() => _errorMessage = localError);
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentPwController.text,
            newPassword: _newPwController.text,
          );
      if (!mounted) return;
      context.go('/home');
    } on Exception catch (e) {
      if (mounted) setState(() => _errorMessage = mapChangeError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _obscuredField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    TextInputAction action = TextInputAction.next,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
      textInputAction: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isForced,
      child: Scaffold(
        backgroundColor: AppColors.surfaceBase,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceBase,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: AppColors.inkPrimary),
          title: Text(
            'Change password',
            style: GoogleFonts.fraunces(
              fontSize: 21, fontWeight: FontWeight.w500, color: AppColors.inkPrimary,
            ),
          ),
          automaticallyImplyLeading: !widget.isForced,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.isForced) ...[
                    Text(
                      'You must change your temporary password before continuing.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  _obscuredField(
                    controller: _currentPwController,
                    label: 'Current Password',
                    visible: _showCurrent,
                    onToggle: () => setState(() => _showCurrent = !_showCurrent),
                  ),
                  const SizedBox(height: 16),
                  _obscuredField(
                    controller: _newPwController,
                    label: 'New Password',
                    visible: _showNew,
                    onToggle: () => setState(() => _showNew = !_showNew),
                  ),
                  const SizedBox(height: 16),
                  _obscuredField(
                    controller: _confirmPwController,
                    label: 'Confirm New Password',
                    visible: _showConfirm,
                    onToggle: () => setState(() => _showConfirm = !_showConfirm),
                    action: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Change Password'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
