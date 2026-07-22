import 'package:flutter/material.dart';

import '../models/vuln_models.dart';
import '../theme/app_theme.dart';

/// "Suggested Solutions" tab -- direct port of VulnRemediationPlan.tsx. The
/// backend already sends this consolidated, prioritized plan on every scan
/// (VulnReport.remediationPlan / WebVulnReport.remediationPlan); this widget
/// was the missing piece, since nothing on the reader rendered it before.
class VulnRemediationPlanView extends StatelessWidget {
  final RemediationPlan plan;
  const VulnRemediationPlanView({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.muted;
    if (plan.steps.isEmpty) {
      return Center(
        child: Text('No actionable remediation steps for this scan. 🎉', style: TextStyle(color: muted)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🛠️ Suggested Solutions',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(plan.summary, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final step in plan.steps) _RemediationStepCard(step: step),
      ],
    );
  }
}

class _RemediationStepCard extends StatelessWidget {
  final RemediationStep step;
  const _RemediationStepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.muted;
    final color = SeverityColors.forSeverity(step.severity);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.action, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(step.severity,
                            style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace')),
                      ),
                      Text(
                        'resolves ${step.affectedCount} finding${step.affectedCount == 1 ? '' : 's'}',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                      if (step.category.isNotEmpty)
                        Text('· ${step.category}', style: TextStyle(color: muted, fontSize: 11)),
                    ],
                  ),
                  if (step.findingTitles.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _AffectedFindings(titles: step.findingTitles),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AffectedFindings extends StatefulWidget {
  final List<String> titles;
  const _AffectedFindings({required this.titles});

  @override
  State<_AffectedFindings> createState() => _AffectedFindingsState();
}

class _AffectedFindingsState extends State<_AffectedFindings> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.muted;
    final preview = widget.titles.take(3).join(', ');
    final more = widget.titles.length > 3 ? ' +${widget.titles.length - 3} more' : '';
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Affected: $preview$more',
              style: TextStyle(color: muted, fontSize: 11, decoration: TextDecoration.underline)),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in widget.titles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $t', style: TextStyle(color: muted, fontSize: 11)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
