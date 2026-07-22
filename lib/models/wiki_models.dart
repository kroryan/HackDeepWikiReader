/// Wiki content models -- mirror api/api.py's WikiPage/WikiSection/
/// WikiStructureModel and src/types/wiki/*.tsx on the web app, and the
/// manifest.json produced by generate_hdwreader_export() (api/api.py).
library;

class WikiPage {
  final String id;
  final String title;
  final String content;
  final List<String> filePaths;
  final String importance; // 'high' | 'medium' | 'low'
  final List<String> relatedPages;

  const WikiPage({
    required this.id,
    required this.title,
    required this.content,
    required this.filePaths,
    required this.importance,
    required this.relatedPages,
  });

  factory WikiPage.fromJson(Map<String, dynamic> json, {String content = ''}) {
    return WikiPage(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: content.isNotEmpty ? content : (json['content'] as String? ?? ''),
      filePaths: (json['filePaths'] as List?)?.map((e) => e as String).toList() ?? [],
      importance: json['importance'] as String? ?? 'medium',
      relatedPages: (json['relatedPages'] as List?)?.map((e) => e as String).toList() ?? [],
    );
  }

  WikiPage copyWithContent(String newContent) => WikiPage(
        id: id,
        title: title,
        content: newContent,
        filePaths: filePaths,
        importance: importance,
        relatedPages: relatedPages,
      );
}

class WikiSection {
  final String id;
  final String title;
  final List<String> pages;
  final List<String> subsections;

  const WikiSection({
    required this.id,
    required this.title,
    required this.pages,
    this.subsections = const [],
  });

  factory WikiSection.fromJson(Map<String, dynamic> json) {
    return WikiSection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      pages: (json['pages'] as List?)?.map((e) => e as String).toList() ?? [],
      subsections: (json['subsections'] as List?)?.map((e) => e as String).toList() ?? [],
    );
  }
}

class WikiStructure {
  final String id;
  final String title;
  final String description;
  final List<WikiPage> pages;
  final List<WikiSection> sections;
  final List<String> rootSections;

  const WikiStructure({
    required this.id,
    required this.title,
    required this.description,
    required this.pages,
    required this.sections,
    required this.rootSections,
  });

  WikiPage? pageById(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// One entry in a connected server's /api/processed_projects list.
class ProcessedProject {
  final String id;
  final String owner;
  final String repo;
  final String name;
  final String repoType;
  final int submittedAt;
  final String language;

  const ProcessedProject({
    required this.id,
    required this.owner,
    required this.repo,
    required this.name,
    required this.repoType,
    required this.submittedAt,
    required this.language,
  });

  factory ProcessedProject.fromJson(Map<String, dynamic> json) {
    return ProcessedProject(
      id: json['id'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      name: json['name'] as String? ?? '',
      repoType: json['repo_type'] as String? ?? 'github',
      submittedAt: json['submittedAt'] as int? ?? 0,
      language: json['language'] as String? ?? 'en',
    );
  }

  bool get isWebsite => repoType == 'website';
}

/// One saved release (version) of a wiki/scan -- mirrors ScanRelease /
/// WikiRelease on the web app (/api/*/releases responses).
class ReleaseInfo {
  final int version;
  final int createdAt;
  final String? title;
  final int? totalFindings;

  const ReleaseInfo({
    required this.version,
    required this.createdAt,
    this.title,
    this.totalFindings,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseInfo(
      version: json['version'] as int? ?? 0,
      createdAt: json['created_at'] as int? ?? 0,
      title: json['title'] as String?,
      totalFindings: json['total_findings'] as int?,
    );
  }
}
