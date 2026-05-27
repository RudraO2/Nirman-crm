import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';

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

  String? _validateLocally() {
    final newPw = _newPwController.text;
    final confirm = _confirmPwController.text;
    if (newPw.length < 8) return 'New password must be at least 8 characters';
    if (!newPw.contains(RegExp(r'[A-Z]'))) {
      return 'New password must contain at least one uppercase letter';
    }
    if (!newPw.contains(RegExp(r'[a-z]'))) {
      return 'New password must contain at least one lowercase letter';
    }
    if (!newPw.contains(RegExp(r'[0-9]'))) {
      return 'New password must contain at least one number';
    }
    if (newPw != confirm) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    final localError = _validateLocally();
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
      setState(() => _errorMessage = _mapError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(String raw) {
    if (raw.contains('Current password is incorrect')) {
      return 'Current password is incorrect.';
    }
    if (raw.contains('at least 8')) {
      return 'New password must be at least 8 characters.';
    }
    if (raw.contains('uppercase')) {
      return 'New password must contain at least one uppercase letter.';
    }
    if (raw.contains('lowercase')) {
      return 'New password must contain at least one lowercase letter.';
    }
    if (raw.contains('number')) {
      return 'New password must contain at least one number.';
    }
    return 'Password change failed. Please try again.';
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
        appBar: AppBar(
          title: const Text('Change Password'),
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
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  _obscuredField(
                    controller: _currentPwController,
                    label: 'Current Password',
                    visible: _showCurrent,
                    onToggle: () =>
                        setState(() => _showCurrent = !_showCurrent),
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
                    onToggle: () =>
                        setState(() => _showConfirm = !_showConfirm),
                    action: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
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
