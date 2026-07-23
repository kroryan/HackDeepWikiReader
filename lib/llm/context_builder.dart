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
/// relevant slice" over "everything". A wiki backed by a large .zim archive
/// can have tens of thousands of pages (a real Wikipedia dump: 17,843) --
/// unconditionally listing every title, like this used to, produces a
/// prompt many times bigger than any model's context window all on its
/// own. [_maxPagesListed] caps that list; the SEARCH_WIKI tool (see
/// [toolCallingInstructions]) is how the model reaches anything not shown.
const _maxPageChars = 6000;
const _maxPagesListed = 40;
const _maxFindingsInPrompt = 25;

/// Mirrors HackDeepWiki's own TOOL_CALLING_INSTRUCTIONS (api/prompts.py) and
/// its agentic loop's provider-agnostic fallback (api/agent_loop.py's
/// sniff_and_relay): a plain-text convention that works identically
/// regardless of provider, since this app -- unlike the backend -- never
/// special-cases specific providers' native function-calling APIs; every
/// LlmClient here already exposes the same "stream plain text" shape (see
/// lib/llm/llm_client.dart), so mirroring the universal fallback covers
/// 100% of this app's providers with one code path. See
/// ChatProvider._sendRound for where a `SEARCH_WIKI:` response is
/// intercepted instead of shown to the user.
///
/// The last two sentences are load-bearing, not just style -- an earlier
/// version of this prompt was missing them (paraphrased instead of copied
/// verbatim from api/prompts.py's TOOL_CALLING_INSTRUCTIONS) and a
/// reasoning-heavy model (confirmed live: Ollama's gpt-oss, which has its
/// OWN native tool-calling training this textual convention doesn't line
/// up with) would sometimes reason about whether to search, get stuck
/// deciding how, and end its turn having emitted nothing at all -- no
/// error, just silence. The web backend's prompt explicitly forbids that
/// outcome ("don't mention tools at all -- just answer with what you
/// have", "answer with whatever you found rather than leaving the user
/// with nothing"); this app's own textual protocol needs the exact same
/// guardrail, since it hits the exact same class of model.
const toolCallingInstructions = '''
## Tools

You have ONE tool available: searching this wiki for pages you don't already have in front of you (useful when the current page doesn't cover something, or the user asks about a different page/topic than the one open).

To use it, your ENTIRE response must be exactly one line, nothing else:
SEARCH_WIKI: <search query>

Do not narrate that you're searching ("Let me look that up...") -- either answer directly, or emit only that one line and nothing else. You'll get the results back and can then answer, search again (up to a few times), or say you couldn't find it. Don't call the tool for things already covered by the context already given to you below.

If you're not going to emit the exact "SEARCH_WIKI: ..." line, don't mention tools at all -- just answer with what you have. Stop searching and answer as soon as you have enough information; do not keep searching just because you still have rounds left. If you reach the round limit without a perfect answer, answer with whatever you found rather than leaving the user with nothing -- an incomplete answer is always better than no answer.
''';

String buildSystemPrompt({
  required String wikiTitle,
  required String wikiDescription,
  required WikiStructure structure,
  required bool isWebsite,
  WikiPage? currentPage,
  VulnReport? vulnReport,
  WebVulnReport? webVulnReport,
  bool includeSecurityContext = false,
  bool allowToolCalling = true,
}) {
  final buffer = StringBuffer();
  // Modeled directly on HackDeepWiki's own chat prompt
  // (api/prompts.py::SIMPLE_CHAT_SYSTEM_PROMPT) -- an earlier, stricter
  // version of this prompt ("answer using ONLY the provided context, say so
  // if something isn't covered") produced exactly the over-literal,
  // refuse-to-engage answers that prompt was rewritten to fix on the
  // backend (e.g. bailing on "what is this?" instead of just answering from
  // the wiki's own title/description). Reusing that same tone here instead
  // of re-deriving a stricter one from scratch.
  buffer.writeln(
    isWebsite
        ? 'You are a helpful, knowledgeable assistant embedded in HackDeepWikiReader, looking '
            'at a wiki generated from the crawled website "$wikiTitle". You have the site\'s '
            "crawled pages (as Markdown) as context below -- there's no source code here, only "
            "page content -- and you're having a real conversation with someone exploring this "
            "site's wiki, not just answering isolated lookup queries."
        : 'You are a helpful, knowledgeable assistant embedded in HackDeepWikiReader, looking '
            'at the wiki "$wikiTitle". You have the wiki\'s generated pages as context below, and '
            "you're having a real conversation with someone exploring it, not just answering "
            'isolated lookup queries.',
  );
  buffer.writeln();
  buffer.writeln(
    '- Detect the language the user is writing in and reply in THAT language, even if it '
    'differs from the wiki\'s own language -- match the user, not a fixed setting.\n'
    '- Have a natural conversation: answer greetings, meta-questions ("what is this?", "what '
    'does this cover?"), and follow-ups directly, using the context below plus your own '
    'reasoning and general knowledge -- you are a chat assistant, not a rigid lookup automaton.\n'
    '- Ground specific claims in the context when it\'s relevant and cite pages/files when it '
    'helps, but if the context doesn\'t fully cover something, say what you do know and reason '
    'about the rest -- never respond with only "I cannot determine this" or refuse to engage.\n'
    '- Answer directly, without unnecessary preamble, filler phrases, or repeating the question.\n'
    '- Use markdown formatting where it helps (headings, lists, code blocks); don\'t start with a '
    '```markdown fence.',
  );
  buffer.writeln();
  buffer.writeln('# Wiki: $wikiTitle');
  if (wikiDescription.isNotEmpty) buffer.writeln(wikiDescription);
  buffer.writeln();

  if (structure.pages.isNotEmpty) {
    buffer.writeln('## Pages in this wiki (${structure.pages.length} total)');
    final shown = structure.pages.take(_maxPagesListed);
    for (final p in shown) {
      buffer.writeln('- ${p.title}${currentPage?.id == p.id ? ' (currently open)' : ''}');
    }
    if (structure.pages.length > _maxPagesListed) {
      buffer.writeln(
          '…and ${structure.pages.length - _maxPagesListed} more, not listed -- use SEARCH_WIKI to find one by topic.');
    }
    buffer.writeln();
  }

  if (currentPage != null) {
    buffer.writeln('## Currently open page: ${currentPage.title}');
    var content = currentPage.content;
    if (content.length > _maxPageChars) {
      content = '${content.substring(0, _maxPageChars)}\n…(truncated -- use SEARCH_WIKI for more of this page or others)';
    }
    buffer.writeln(content);
    buffer.writeln();
  }

  if (allowToolCalling && structure.pages.isNotEmpty) {
    buffer.writeln(toolCallingInstructions);
  } else if (!allowToolCalling && structure.pages.isNotEmpty) {
    // Mirrors api/agent_loop.py's is_last_round note -- without an explicit
    // instruction, simply omitting the tool block leaves the model to
    // infer on its own that it can't search anymore, which a reasoning
    // model can spend its whole turn puzzling over instead of just
    // answering (see toolCallingInstructions' doc for the related, more
    // common failure this app hit).
    buffer.writeln(
      'You have used all available searches for this answer. Answer now '
      'using the information already gathered -- do not request another '
      'search.',
    );
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
  if (report.exploitationPlan.summary.isNotEmpty) {
    buffer.writeln('Exploitation playbook summary: ${report.exploitationPlan.summary}');
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
  if (report.exploitationPlan.summary.isNotEmpty) {
    buffer.writeln('Exploitation playbook summary: ${report.exploitationPlan.summary}');
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
