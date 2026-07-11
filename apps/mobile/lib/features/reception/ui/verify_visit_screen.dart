// Story 13.4-mobile — reception check-in screen.
//
// A receptionist (or builder_head) enters a customer's visit code and taps Verify.
// The screen calls verify_visit (RPC-authoritative) and shows only the new visit
// ordinal + the entered code — NO lead PII (the receptionist is gate-not-own, 12.6).
// Entry is best-effort role-gated in you_screen; the RPC re-checks the tier server-side.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
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
          style: GoogleFonts.fraunces(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
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

          // ── Last verified result ────────────────────────────────────
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            _VerifiedCard(result: _lastResult!, code: _lastCode ?? ''),
          ],
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

class _VerifiedCard extends StatelessWidget {
  final VisitResult result;
  final String code;
  const _VerifiedCard({required this.result, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.statusFutureBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.evergreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.evergreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.how_to_reg_rounded,
                size: 22, color: AppColors.brassBright),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit recorded',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$code · ${result.ordinalLabel}',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
