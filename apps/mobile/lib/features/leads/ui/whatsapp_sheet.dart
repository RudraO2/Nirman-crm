// Story 3.4 — WhatsApp send via template
// Template picker → client-side variable render → confirm modal (phone = largest element) → wa.me/ deep link.
// Logs whatsapp_sent timeline event on send.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';

// The logged-in sender's display name for the {{agent_name}} token, derived from
// their username the same way the You tab does (email local-part), title-cased so
// "sangeeta@employees.nirman.local" reads as "Sangeeta" in the message.
String _senderName(WidgetRef ref) {
  final email = ref.read(authRepositoryProvider).currentSession?.user.email ?? '';
  final local = email.contains('@') ? email.split('@').first : email;
  if (local.isEmpty) return '';
  return local
      .split(RegExp(r'[._\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

Future<void> showWhatsAppSheet(BuildContext context, LeadDetail lead) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WhatsAppSheet(lead: lead),
  );
}

class _WhatsAppSheet extends ConsumerStatefulWidget {
  final LeadDetail lead;
  const _WhatsAppSheet({required this.lead});

  @override
  ConsumerState<_WhatsAppSheet> createState() => _WhatsAppSheetState();
}

class _WhatsAppSheetState extends ConsumerState<_WhatsAppSheet> {
  WhatsAppTemplate? _selected;
  bool _loading   = false;
  bool _sending   = false;
  bool _showConfirm = false;
  List<WhatsAppTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(leadRepositoryProvider).fetchWhatsAppTemplates();
      if (mounted) setState(() { _templates = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _renderedBody() {
    if (_selected == null) return '';
    final lead = widget.lead;
    String budget = '';
    if (lead.budgetMin != null && lead.budgetMax != null) {
      budget = '₹${(lead.budgetMin! / 100).round()}–₹${(lead.budgetMax! / 100).round()}';
    } else if (lead.budgetMin != null) {
      budget = '₹${(lead.budgetMin! / 100).round()}+';
    }
    final projects = ref.read(availableProjectsProvider).valueOrNull;
    final projectNames = projects
        ?.where((p) => lead.projectIds.contains(p.id))
        .map((p) => p.name)
        .join(', ');
    return _selected!.render(
      name:         lead.name,
      phone:        lead.displayPhone,
      propertyType: lead.propertyType,
      ticketSize:   lead.ticketSize,
      budget:       budget.isEmpty ? null : budget,
      projects:     (projectNames == null || projectNames.isEmpty) ? null : projectNames,
      status:       lead.status,
      followupDate: lead.nextFollowupAt == null
          ? null
          : DateFormat('EEE d MMM, h:mm a').format(lead.nextFollowupAt!.toLocal()),
      agentName:    _senderName(ref),
    );
  }

  Future<void> _send() async {
    final phone    = widget.lead.phone;
    final template = _selected;
    if (phone == null || template == null) return;
    setState(() => _sending = true);
    try {
      final body = _renderedBody();
      // Log timeline event
      await ref.read(leadRepositoryProvider).logWhatsAppSent(
        leadId:       widget.lead.id,
        templateName: template.name,
        renderedBody: body,
        recipientPhone: phone,
      );
      ref.invalidate(myLeadsProvider);
      ref.invalidate(leadByIdProvider(widget.lead.id));
      // Open WhatsApp — wa.me needs the country code; leads store raw 10-digit
      // Indian numbers (same 91-prefix rule as the create-lead edge fn).
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      final e164 = digits.length == 10 ? '91$digits' : digits;
      final encoded = Uri.encodeComponent(body);
      final uri = Uri.parse('https://wa.me/$e164?text=$encoded');
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send WhatsApp message.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: _showConfirm ? _ConfirmView(
        lead: widget.lead,
        template: _selected!,
        renderedBody: _renderedBody(),
        sending: _sending,
        onConfirm: _send,
        onBack: () => setState(() => _showConfirm = false),
      ) : _PickerView(
        templates: _templates,
        loading: _loading,
        selected: _selected,
        onSelect: (t) => setState(() => _selected = t),
        onNext: _selected == null ? null : () => setState(() => _showConfirm = true),
      ),
    );
  }
}

class _PickerView extends StatelessWidget {
  final List<WhatsAppTemplate> templates;
  final bool loading;
  final WhatsAppTemplate? selected;
  final ValueChanged<WhatsAppTemplate> onSelect;
  final VoidCallback? onNext;

  const _PickerView({
    required this.templates, required this.loading,
    required this.selected, required this.onSelect, required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 42, height: 4.5, decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(99)))),
        const SizedBox(height: 16),
        Text('Send WhatsApp', style: AppType.display(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.inkPrimary)),
        const SizedBox(height: 4),
        Text('Pick a template', style: TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
        const SizedBox(height: 16),
        if (loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (templates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No templates set up yet. Ask your admin.', style: TextStyle(color: AppColors.inkSecondary, fontSize: 14)),
          )
        else
          ...templates.map((t) {
            final sel = t.id == selected?.id;
            return GestureDetector(
              onTap: () => onSelect(t),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sel ? AppColors.accentStrong.withOpacity(0.06) : AppColors.surfaceBase,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? AppColors.accentStrong.withOpacity(0.5) : AppColors.borderHairline, width: sel ? 1.5 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: sel ? AppColors.accentStrong : AppColors.inkPrimary)),
                  const SizedBox(height: 4),
                  Text(t.body, style: TextStyle(fontSize: 12, color: AppColors.inkSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            );
          }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentStrong,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.accentStrong.withOpacity(0.3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Preview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _ConfirmView extends StatelessWidget {
  final LeadDetail lead;
  final WhatsAppTemplate template;
  final String renderedBody;
  final bool sending;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  const _ConfirmView({
    required this.lead, required this.template, required this.renderedBody,
    required this.sending, required this.onConfirm, required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 42, height: 4.5, decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(99)))),
        const SizedBox(height: 16),
        Row(children: [
          GestureDetector(onTap: onBack, child: Icon(Icons.arrow_back_rounded, color: AppColors.inkSecondary, size: 20)),
          const SizedBox(width: 8),
          Text('Confirm send', style: AppType.display(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.inkPrimary)),
        ]),
        const SizedBox(height: 20),
        // Phone = largest element per Story 3.4 AC
        Center(
          child: Text(
            lead.displayPhone,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.inkPrimary, letterSpacing: 1),
          ),
        ),
        if (lead.name != null)
          Center(child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(lead.name!, style: TextStyle(fontSize: 15, color: AppColors.inkSecondary)),
          )),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceBase,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(template.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSecondary, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Text(renderedBody, style: TextStyle(fontSize: 14, color: AppColors.inkPrimary, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: sending ? null : onConfirm,
            icon: sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send via WhatsApp', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF25D366).withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
