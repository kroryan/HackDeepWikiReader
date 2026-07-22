import 'package:flutter/material.dart';

import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../models/wiki_models.dart';
import '../providers/wiki_source.dart';
import '../theme/app_theme.dart';
import '../widgets/vuln_graph_2d.dart';

/// Read-only Security Analysis / Website Security viewer -- direct port of
/// VulnSection.tsx / WebVulnSection.tsx: overview stats, tabbed findings,
/// finding detail, graph, Scan History. No "Run scan"/"Rerun scan" button
/// exists here -- this app never triggers scans, only reads saved ones.
class SecurityScreen extends StatefulWidget {
  final WikiSource source;
  const SecurityScreen({super.key, required this.source});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  VulnReport? _vulnReport;
  WebVulnReport? _webVulnReport;
  List<ReleaseInfo> _releases = [];
  int? _selectedVersion;
  bool _loading = true;
  String? _error;

  bool get _isWebsite => widget.source.isWebsite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? version}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isWebsite) {
        final report = await widget.source.loadWebVulnReport(version: version);
        final releases = await widget.source.loadWebVulnReleases();
        setState(() {
          _webVulnReport = report;
          _releases = releases;
          _selectedVersion = version ?? (releases.isNotEmpty ? releases.first.version : null);
        });
      } else {
        final report = await widget.source.loadVulnReport(version: version);
        final releases = await widget.source.loadVulnReleases();
        setState(() {
          _vulnReport = report;
          _releases = releases;
          _selectedVersion = version ?? (releases.isNotEmpty ? releases.first.version : null);
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isWebsite ? 'Website Security' : 'Security Analysis')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error'))
              : _isWebsite
                  ? _buildWebReport(context)
                  : _buildDepReport(context),
    );
  }

  Widget _releaseSelector() {
    if (_releases.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int>(
              isExpanded: true,
              value: _selectedVersion,
              items: [
                for (final r in _releases)
                  DropdownMenuItem(
                    value: r.version,
                    child: Text('v${r.version} — ${r.totalFindings ?? '?'} findings'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _load(version: v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepReport(BuildContext context) {
    final report = _vulnReport;
    if (report == null) {
      return const Center(child: Text('No vulnerability scan available for this wiki.'));
    }
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _releaseSelector(),
          _OverviewCard(counts: report.counts, extra: {
            'Total findings': '${report.totalFindings}',
            'Dependencies scanned': '${report.totalDependenciesScanned}',
          }),
          const TabBar(tabs: [
            Tab(text: 'Client'),
            Tab(text: 'Server'),
            Tab(text: 'Dependencies'),
            Tab(text: 'Graph'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _CveFindingsList(findings: report.clientFindings),
              _CveFindingsList(findings: report.serverFindings),
              _CveFindingsList(findings: report.dependencyFindings),
              VulnGraph2DView(graph: report.graph, onNodeTap: (n) => _showCveNodeDetail(report, n.id)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildWebReport(BuildContext context) {
    final report = _webVulnReport;
    if (report == null) {
      return const Center(child: Text('No website security scan available for this wiki.'));
    }
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          _releaseSelector(),
          _OverviewCard(counts: report.counts, extra: {
            'Total findings': '${report.totalFindings}',
            'Pages scanned': '${report.pagesScanned}',
            'Deep scan (Docker)': report.deepScanRan ? 'yes' : 'no',
          }),
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Headers'),
            Tab(text: 'Cookies'),
            Tab(text: 'TLS'),
            Tab(text: 'Exposure'),
            Tab(text: 'Graph'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _WebFindingsList(findings: report.headerFindings),
              _WebFindingsList(findings: report.cookieFindings),
              _WebFindingsList(findings: report.tlsFindings),
              _WebFindingsList(findings: report.exposureFindings),
              VulnGraph2DView(graph: report.graph),
            ]),
          ),
        ],
      ),
    );
  }

  void _showCveNodeDetail(VulnReport report, String nodeId) {
    final rawId = nodeId.replaceFirst(RegExp(r'^cve:'), '');
    CVEFinding? finding;
    for (final f in report.allFindings) {
      if (f.id == rawId) {
        finding = f;
        break;
      }
    }
    if (finding != null) _showCveDetailSheet(context, finding);
  }
}

class _OverviewCard extends StatelessWidget {
  final Map<String, int> counts;
  final Map<String, String> extra;
  const _OverviewCard({required this.counts, required this.extra});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in counts.entries)
                if (entry.value > 0)
                  Chip(
                    label: Text('${entry.key}: ${entry.value}'),
                    backgroundColor: SeverityColors.forSeverity(entry.key).withValues(alpha: 0.2),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              for (final e in extra.entries)
                Text('${e.key}: ${e.value}', style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CveFindingsList extends StatelessWidget {
  final List<CVEFinding> findings;
  const _CveFindingsList({required this.findings});

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) {
      return const Center(child: Text('No vulnerabilities in this category. 🎉'));
    }
    return ListView.builder(
      itemCount: findings.length,
      itemBuilder: (context, i) {
        final f = findings[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: SeverityColors.forSeverity(f.severity), radius: 6),
            title: Text('${f.id} — ${f.packageName}@${f.installedVersion}'),
            subtitle: Text(f.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _showCveDetailSheet(context, f),
          ),
        );
      },
    );
  }
}

class _WebFindingsList extends StatelessWidget {
  final List<WebFinding> findings;
  const _WebFindingsList({required this.findings});

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) {
      return const Center(child: Text('No findings in this category. 🎉'));
    }
    return ListView.builder(
      itemCount: findings.length,
      itemBuilder: (context, i) {
        final f = findings[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: SeverityColors.forSeverity(f.severity), radius: 6),
            title: Text(f.title),
            subtitle: Text(f.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _showWebDetailSheet(context, f),
          ),
        );
      },
    );
  }
}

void _showCveDetailSheet(BuildContext context, CVEFinding f) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text(f.id, style: Theme.of(context).textTheme.titleLarge),
          Text('${f.packageName}@${f.installedVersion} (${f.packageEcosystem})'),
          if (f.fixedVersion != null) Text('Fixed in: ${f.fixedVersion}'),
          const Divider(),
          Text('Summary', style: Theme.of(context).textTheme.labelLarge),
          Text(f.summary),
          if (f.aiImpactAnalysis.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('📊 Impact analysis', style: Theme.of(context).textTheme.labelLarge),
            Text(f.aiImpactAnalysis),
          ],
          if (f.aiExploitability.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('⚔️ Exploitability', style: Theme.of(context).textTheme.labelLarge),
            Text(f.aiExploitability),
          ],
          if (f.aiRemediation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('🛠️ Remediation', style: Theme.of(context).textTheme.labelLarge),
            Text(f.aiRemediation),
          ],
          if (f.usageFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('📁 Used in', style: Theme.of(context).textTheme.labelLarge),
            for (final path in f.usageFiles) Text(path, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ],
      ),
    ),
  );
}

void _showWebDetailSheet(BuildContext context, WebFinding f) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text(f.title, style: Theme.of(context).textTheme.titleLarge),
          Text(f.url),
          const Divider(),
          Text('Description', style: Theme.of(context).textTheme.labelLarge),
          Text(f.description),
          if (f.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Evidence', style: Theme.of(context).textTheme.labelLarge),
            Text(f.evidence, style: const TextStyle(fontFamily: 'monospace')),
          ],
          if (f.remediation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('🛠️ Remediation', style: Theme.of(context).textTheme.labelLarge),
            Text(f.remediation),
          ],
        ],
      ),
    ),
  );
}
