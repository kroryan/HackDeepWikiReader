/// Website security scan models -- mirror src/components/vuln/webTypes.ts
/// on the web app, which mirror api/web_vuln_scanner/models.py.
library;

import 'vuln_models.dart' show ExploitationPlan, GraphData, RemediationPlan;

class WebFinding {
  final String id;
  final String category; // headers | cookies | tls | exposure | cve
  final String severity; // CRITICAL | HIGH | MEDIUM | LOW | INFO
  final String title;
  final String description;
  final String url;
  final String evidence;
  final String remediation;
  final List<String> references;
  final String? cveId;
  final double? cvssScore;
  final String? technology;
  final String? technologyVersion;
  final bool aiProposed;
  final bool aiDismissed;
  final String aiDismissReason;
  final String aiNotes;
  // Same trio as CVEFinding, so both scan types share one exploitation UI.
  final String aiExploitability;
  final String aiExploitVector;
  final String aiExploitPlan;

  const WebFinding({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    required this.url,
    required this.evidence,
    required this.remediation,
    required this.references,
    this.cveId,
    this.cvssScore,
    this.technology,
    this.technologyVersion,
    required this.aiProposed,
    required this.aiDismissed,
    required this.aiDismissReason,
    required this.aiNotes,
    required this.aiExploitability,
    required this.aiExploitVector,
    required this.aiExploitPlan,
  });

  factory WebFinding.fromJson(Map<String, dynamic> json) {
    return WebFinding(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? '',
      severity: json['severity'] as String? ?? 'INFO',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      url: json['url'] as String? ?? '',
      evidence: json['evidence'] as String? ?? '',
      remediation: json['remediation'] as String? ?? '',
      references: (json['references'] as List?)?.map((e) => e as String).toList() ?? [],
      cveId: json['cve_id'] as String?,
      cvssScore: (json['cvss_score'] as num?)?.toDouble(),
      technology: json['technology'] as String?,
      technologyVersion: json['technology_version'] as String?,
      aiProposed: json['ai_proposed'] as bool? ?? false,
      aiDismissed: json['ai_dismissed'] as bool? ?? false,
      aiDismissReason: json['ai_dismiss_reason'] as String? ?? '',
      aiNotes: json['ai_notes'] as String? ?? '',
      aiExploitability: json['ai_exploitability'] as String? ?? '',
      aiExploitVector: json['ai_exploit_vector'] as String? ?? '',
      aiExploitPlan: json['ai_exploit_plan'] as String? ?? '',
    );
  }
}

class DetectedTechnology {
  final String name;
  const DetectedTechnology(this.name);
  factory DetectedTechnology.fromJson(Map<String, dynamic> json) =>
      DetectedTechnology(json['name'] as String? ?? '');
}

class WebVulnReport {
  final String siteUrl;
  final String owner;
  final String repo;
  final String language;
  final String generatedAt;
  final String provider;
  final String model;
  final int pagesScanned;
  final Map<String, int> counts;
  final int totalFindings;
  final List<WebFinding> headerFindings;
  final List<WebFinding> cookieFindings;
  final List<WebFinding> tlsFindings;
  final List<WebFinding> exposureFindings;
  final List<WebFinding> cveFindings;
  final List<WebFinding> allFindings;
  final List<DetectedTechnology> detectedTechnologies;
  final bool aiAnalyzed;
  final bool deepScanRan;
  final GraphData graph;
  final RemediationPlan remediationPlan;
  final ExploitationPlan exploitationPlan;

  const WebVulnReport({
    required this.siteUrl,
    required this.owner,
    required this.repo,
    required this.language,
    required this.generatedAt,
    required this.provider,
    required this.model,
    required this.pagesScanned,
    required this.counts,
    required this.totalFindings,
    required this.headerFindings,
    required this.cookieFindings,
    required this.tlsFindings,
    required this.exposureFindings,
    required this.cveFindings,
    required this.allFindings,
    required this.detectedTechnologies,
    required this.aiAnalyzed,
    required this.deepScanRan,
    required this.graph,
    required this.remediationPlan,
    required this.exploitationPlan,
  });

  factory WebVulnReport.fromJson(Map<String, dynamic> json) {
    List<WebFinding> findings(String key) =>
        (json[key] as List?)?.map((e) => WebFinding.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    return WebVulnReport(
      siteUrl: json['site_url'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      generatedAt: json['generated_at'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      pagesScanned: json['pages_scanned'] as int? ?? 0,
      counts: (json['counts'] as Map?)?.map((k, v) => MapEntry(k as String, v as int)) ?? {},
      totalFindings: json['total_findings'] as int? ?? 0,
      headerFindings: findings('header_findings'),
      cookieFindings: findings('cookie_findings'),
      tlsFindings: findings('tls_findings'),
      exposureFindings: findings('exposure_findings'),
      cveFindings: findings('cve_findings'),
      allFindings: findings('all_findings'),
      detectedTechnologies: (json['detected_technologies'] as List?)
              ?.map((e) => DetectedTechnology.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      aiAnalyzed: json['ai_analyzed'] as bool? ?? false,
      deepScanRan: json['deep_scan_ran'] as bool? ?? false,
      graph: GraphData.fromJson(json['graph'] as Map<String, dynamic>?),
      remediationPlan: RemediationPlan.fromJson(json['remediation_plan'] as Map<String, dynamic>?),
      exploitationPlan: ExploitationPlan.fromJson(json['exploitation_plan'] as Map<String, dynamic>?),
    );
  }
}
