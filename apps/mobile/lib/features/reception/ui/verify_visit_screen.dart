// Story 13.4-mobile — reception check-in screen.
//
// A receptionist (or builder_head) enters a customer's visit code and taps Verify.
// The screen calls verify_visit (RPC-authoritative) and shows only the new visit
// ordinal + the entered code — NO lead PII (the receptionist is gate-not-own, 12.6).
// Entry is best-effort role-gated in you_screen; the RPC re-checks the tier server-side.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../data/models/visit_result.dart';
import '../data/reception_repository.dart';

class VerifyVisitScreen extends ConsumerStatefulWidget {
  const VerifyVisitScreen({super.key});

  @override
  ConsumerState<VerifyVisitScreen> createState() => _VerifyVisitScreenState();
}

class _VerifyVisitScreenState extends ConsumerState<VerifyVisitScreen> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _errorMsg;
  VisitResult? _lastResult;
  String? _lastCode;

  bool get _canSubmit =>
      !_submitting && _codeCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_canSubmit) return;
    final entered = ReceptionRepository.normalizeCode(_codeCtrl.text);
    setState(() {
      _submitting = true;
      _errorMsg = null;
      _lastResult = null; // drop any prior success so it can't sit above a new error
    });
    try {
      final result =
          await ref.read(receptionRepositoryProvider).verifyVisit(entered);
      if (!mounted) return;
      // A4 — the receptionist is at a desk with the customer watching: make
      // success felt, not just printed.
      HapticFeedback.mediumImpact();
      setState(() {
        _lastResult = result;
        _lastCode = entered;
        _submitting = false;
        _codeCtrl.clear(); // ready for the next walk-in
      });
    } on VerifyVisitException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.friendly;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = "Couldn't verify that code. Try again.";
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // B1 — for a receptionist this screen IS the app (router lands her here;
    // the 3-tab shell is server-denied for her). She still needs the two You-tab
    // basics, so they live in a small menu here. Other roles arrive from the
    // You tab and keep using it; no menu for them.
    final isReceptionist = ref
            .read(authRepositoryProvider)
            .currentSession
            ?.user
            .appMetadata['role_tier'] ==
        'receptionist';

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Reception check-in',
          style: AppType.display(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
        actions: [
          if (isReceptionist)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.inkSecondary),
              onSelected: (v) {
                if (v == 'password') {
                  context.push('/password-change?forced=false');
                } else if (v == 'logout') {
                  ref.read(authRepositoryProvider).signOut();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'password',
                  child: Text('Change password'),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Text('Log out'),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // A4 — success panel at the TOP, unmissable at desk distance.
          if (_lastResult != null) ...[
            _VerifiedPanel(result: _lastResult!, code: _lastCode ?? ''),
            const SizedBox(height: 20),
          ],
          Text(
            'Enter the code the customer received when they registered. '
            'Verifying records their visit against the right lead.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.inkSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // ── Code field ──────────────────────────────────────────────
          Text(
            'Visit code',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _codeCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _verify(),
            inputFormatters: [_UpperCaseFormatter()],
            style: GoogleFonts.firaCode(
              color: AppColors.inkPrimary,
              fontSize: 20,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'NIR-XXXXX',
              hintStyle: TextStyle(color: AppColors.inkDisabled, letterSpacing: 2),
              errorText: _errorMsg,
              errorStyle: TextStyle(color: AppColors.error, fontSize: 12),
              filled: true,
              fillColor: AppColors.paper,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.brass, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.error, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.error, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
          const SizedBox(height: 16),

          // ── Verify button ───────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _canSubmit ? _verify : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.evergreen,
                foregroundColor: AppColors.brassBright,
                disabledBackgroundColor: AppColors.surfaceMist,
                disabledForegroundColor: AppColors.inkDisabled,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(AppColors.brassBright),
                      ),
                    )
                  : const Text(
                      'Verify visit',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),

        ],
      ),
    );
  }
}

/// Forces every keystroke to uppercase in place (keeps the caret at the end).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// A4 — big, desk-distance success panel. Replaces the old quiet row card:
/// the receptionist (with the customer watching) must SEE that it worked.
class _VerifiedPanel extends StatelessWidget {
  final VisitResult result;
  final String code;
  const _VerifiedPanel({required this.result, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.evergreen,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.brassSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 40, color: Color(0xFF2E5240)),
          ),
          const SizedBox(height: 14),
          Text(
            'Visit verified',
            style: AppType.display(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF2EEE2),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$code · ${result.ordinalLabel}',
            style: GoogleFonts.firaCode(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.brassBright,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ready for the next customer',
            style: TextStyle(
              fontSize: 12.5,
              color: const Color(0xFFE9E4D6).withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
