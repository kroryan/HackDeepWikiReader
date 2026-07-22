import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../models/wiki_models.dart';

/// Turns locally-available wiki data into the system prompt sent to an LLM.
/// This app has no server-side RAG pipeline to lean on (unlike the web
/// app's /ws/chat, which retrieves context on the backend) -- so it builds
/// its own, deliberately simple context directly from the WikiSource
/// already loaded in memory: the wiki's page list (so the model knows what
/// else exists), the full content of the page currently open, and
/// (optionally, mirroring the web app's 🔐 Security-context toggle)
/// a condensed summary of the security report.
///
/// Kept bounded in size on purpose -- most local models (the Ollama case
/// especially) have small context windows, so this favors "a focused,
/// relevant slice" over "everything".
const _maxPageChars = 12000;
const _maxFindingsInPrompt = 25;

String buildSystemPrompt({
  required String wikiTitle,
  required String wikiDescription,
  required WikiStructure structure,
  WikiPage? currentPage,
  VulnReport? vulnReport,
  WebVulnReport? webVulnReport,
  bool includeSecurityContext = false,
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    'You are a helpful assistant embedded in HackDeepWikiReader, a read-only wiki '
    'viewer. Answer questions about the wiki below using only the context provided. '
    "If something isn't covered by the context, say so instead of guessing.",
  );
  buffer.writeln();
  buffer.writeln('# Wiki: $wikiTitle');
  if (wikiDescription.isNotEmpty) buffer.writeln(wikiDescription);
  buffer.writeln();

  if (structure.pages.isNotEmpty) {
    buffer.writeln('## Pages in this wiki');
    for (final p in structure.pages) {
      buffer.writeln('- ${p.title}${currentPage?.id == p.id ? ' (currently open)' : ''}');
    }
    buffer.writeln();
  }

  if (currentPage != null) {
    buffer.writeln('## Currently open page: ${currentPage.title}');
    var content = currentPage.content;
    if (content.length > _maxPageChars) {
      content = '${content.substring(0, _maxPageChars)}\n…(truncated)';
    }
    buffer.writeln(content);
    buffer.writeln();
  }

  if (includeSecurityContext) {
    if (vulnReport != null) buffer.writeln(_summarizeVulnReport(vulnReport));
    if (webVulnReport != null) buffer.writeln(_summarizeWebVulnReport(webVulnReport));
  }

  return buffer.toString();
}

String _summarizeVulnReport(VulnReport report) {
  final buffer = StringBuffer();
  buffer.writeln('## Security Analysis (dependency scan)');
  buffer.writeln(
    'Generated ${report.generatedAt}. ${report.totalFindings} findings across '
    '${report.totalDependenciesScanned} scanned dependencies. Counts by severity: ${report.counts}.',
  );
  if (report.remediationPlan.summary.isNotEmpty) {
    buffer.writeln('Remediation summary: ${report.remediationPlan.summary}');
  }
  final findings = report.allFindings.take(_maxFindingsInPrompt);
  for (final f in findings) {
    buffer.writeln(
      '- [${f.severity}] ${f.id} in ${f.packageName}@${f.installedVersion}'
      '${f.fixedVersion != null ? ' (fix: ${f.fixedVersion})' : ''}: ${f.summary}',
    );
  }
  if (report.allFindings.length > _maxFindingsInPrompt) {
    buffer.writeln('…and ${report.allFindings.length - _maxFindingsInPrompt} more findings not shown.');
  }
  buffer.writeln();
  return buffer.toString();
}

String _summarizeWebVulnReport(WebVulnReport report) {
  final buffer = StringBuffer();
  buffer.writeln('## Website Security scan (${report.siteUrl})');
  buffer.writeln(
    'Generated ${report.generatedAt}. Scanned ${report.pagesScanned} pages, '
    '${report.totalFindings} findings. Counts by severity: ${report.counts}.',
  );
  if (report.detectedTechnologies.isNotEmpty) {
    buffer.writeln('Detected technologies: ${report.detectedTechnologies.map((t) => t.name).join(', ')}.');
  }
  if (report.remediationPlan.summary.isNotEmpty) {
    buffer.writeln('Remediation summary: ${report.remediationPlan.summary}');
  }
  final findings = report.allFindings.take(_maxFindingsInPrompt);
  for (final f in findings) {
    buffer.writeln('- [${f.severity}] (${f.category}) ${f.title} — ${f.url}: ${f.description}');
  }
  if (report.allFindings.length > _maxFindingsInPrompt) {
    buffer.writeln('…and ${report.allFindings.length - _maxFindingsInPrompt} more findings not shown.');
  }
  buffer.writeln();
  return buffer.toString();
}
