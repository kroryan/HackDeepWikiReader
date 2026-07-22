/// Dependency vulnerability scan models -- mirror
/// src/components/vuln/types.ts (VulnReport/CVEFinding/GraphData) on the web
/// app, which mirror api/vuln_scanner/models.py on the backend.
library;

class GraphNode {
  final String id;
  final String type; // package | cve | file | cwe | fix | site | technology | category | finding
  final String label;
  final String? severity;
  final double? cvssScore;
  final int? cveCount;

  const GraphNode({
    required this.id,
    required this.type,
    required this.label,
    this.severity,
    this.cvssScore,
    this.cveCount,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      severity: json['severity'] as String?,
      cvssScore: (json['cvss_score'] as num?)?.toDouble(),
      cveCount: json['cve_count'] as int?,
    );
  }
}

class GraphLink {
  final String source;
  final String target;
  final String label;

  const GraphLink({required this.source, required this.target, required this.label});

  factory GraphLink.fromJson(Map<String, dynamic> json) {
    return GraphLink(
      source: json['source'] as String? ?? '',
      target: json['target'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

class GraphData {
  final List<GraphNode> nodes;
  final List<GraphLink> links;

  const GraphData({this.nodes = const [], this.links = const []});

  factory GraphData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GraphData();
    return GraphData(
      nodes: (json['nodes'] as List?)?.map((e) => GraphNode.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      links: (json['links'] as List?)?.map((e) => GraphLink.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }
}

class CVEFinding {
  final String id;
  final List<String> aliases;
  final String packageName;
  final String packageEcosystem;
  final String installedVersion;
  final String? fixedVersion;
  final String severity;
  final double? cvssScore;
  final String summary;
  final String details;
  final List<String> references;
  final List<String> cweIds;
  final String category; // client | server | dependency
  final List<String> usageFiles;
  final String aiImpactAnalysis;
  final String aiExploitability;
  final String aiRemediation;
  final int aiPriority;

  const CVEFinding({
    required this.id,
    required this.aliases,
    required this.packageName,
    required this.packageEcosystem,
    required this.installedVersion,
    required this.fixedVersion,
    required this.severity,
    required this.cvssScore,
    required this.summary,
    required this.details,
    required this.references,
    required this.cweIds,
    required this.category,
    required this.usageFiles,
    required this.aiImpactAnalysis,
    required this.aiExploitability,
    required this.aiRemediation,
    required this.aiPriority,
  });

  factory CVEFinding.fromJson(Map<String, dynamic> json) {
    return CVEFinding(
      id: json['id'] as String? ?? '',
      aliases: (json['aliases'] as List?)?.map((e) => e as String).toList() ?? [],
      packageName: json['package_name'] as String? ?? '',
      packageEcosystem: json['package_ecosystem'] as String? ?? '',
      installedVersion: json['installed_version'] as String? ?? '',
      fixedVersion: json['fixed_version'] as String?,
      severity: json['severity'] as String? ?? 'UNKNOWN',
      cvssScore: (json['cvss_score'] as num?)?.toDouble(),
      summary: json['summary'] as String? ?? '',
      details: json['details'] as String? ?? '',
      references: (json['references'] as List?)?.map((e) => e as String).toList() ?? [],
      cweIds: (json['cwe_ids'] as List?)?.map((e) => e as String).toList() ?? [],
      category: json['category'] as String? ?? 'dependency',
      usageFiles: (json['usage_files'] as List?)?.map((e) => e as String).toList() ?? [],
      aiImpactAnalysis: json['ai_impact_analysis'] as String? ?? '',
      aiExploitability: json['ai_exploitability'] as String? ?? '',
      aiRemediation: json['ai_remediation'] as String? ?? '',
      aiPriority: json['ai_priority'] as int? ?? 3,
    );
  }
}

class RemediationStep {
  final String action;
  final String severity;
  final List<String> findingIds;
  final String category;
  final int affectedCount;

  const RemediationStep({
    required this.action,
    required this.severity,
    required this.findingIds,
    required this.category,
    required this.affectedCount,
  });

  factory RemediationStep.fromJson(Map<String, dynamic> json) {
    return RemediationStep(
      action: json['action'] as String? ?? '',
      severity: json['severity'] as String? ?? 'INFO',
      findingIds: (json['finding_ids'] as List?)?.map((e) => e as String).toList() ?? [],
      category: json['category'] as String? ?? '',
      affectedCount: json['affected_count'] as int? ?? 0,
    );
  }
}

class RemediationPlan {
  final List<RemediationStep> steps;
  final String summary;
  final int totalFindingsCovered;

  const RemediationPlan({required this.steps, required this.summary, required this.totalFindingsCovered});

  factory RemediationPlan.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RemediationPlan(steps: [], summary: '', totalFindingsCovered: 0);
    return RemediationPlan(
      steps: (json['steps'] as List?)?.map((e) => RemediationStep.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      summary: json['summary'] as String? ?? '',
      totalFindingsCovered: json['total_findings_covered'] as int? ?? 0,
    );
  }
}

class VulnReport {
  final String repoUrl;
  final String repoType;
  final String owner;
  final String repo;
  final String language;
  final String generatedAt;
  final String provider;
  final String model;
  final Map<String, int> counts;
  final int totalFindings;
  final int totalDependenciesScanned;
  final List<CVEFinding> clientFindings;
  final List<CVEFinding> serverFindings;
  final List<CVEFinding> dependencyFindings;
  final List<CVEFinding> allFindings;
  final GraphData graph;
  final bool aiAnalyzed;
  final RemediationPlan remediationPlan;

  const VulnReport({
    required this.repoUrl,
    required this.repoType,
    required this.owner,
    required this.repo,
    required this.language,
    required this.generatedAt,
    required this.provider,
    required this.model,
    required this.counts,
    required this.totalFindings,
    required this.totalDependenciesScanned,
    required this.clientFindings,
    required this.serverFindings,
    required this.dependencyFindings,
    required this.allFindings,
    required this.graph,
    required this.aiAnalyzed,
    required this.remediationPlan,
  });

  factory VulnReport.fromJson(Map<String, dynamic> json) {
    List<CVEFinding> findings(String key) =>
        (json[key] as List?)?.map((e) => CVEFinding.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    return VulnReport(
      repoUrl: json['repo_url'] as String? ?? '',
      repoType: json['repo_type'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      generatedAt: json['generated_at'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      counts: (json['counts'] as Map?)?.map((k, v) => MapEntry(k as String, v as int)) ?? {},
      totalFindings: json['total_findings'] as int? ?? 0,
      totalDependenciesScanned: json['total_dependencies_scanned'] as int? ?? 0,
      clientFindings: findings('client_findings'),
      serverFindings: findings('server_findings'),
      dependencyFindings: findings('dependency_findings'),
      allFindings: findings('all_findings'),
      graph: GraphData.fromJson(json['graph'] as Map<String, dynamic>?),
      aiAnalyzed: json['ai_analyzed'] as bool? ?? false,
      remediationPlan: RemediationPlan.fromJson(json['remediation_plan'] as Map<String, dynamic>?),
    );
  }
}
