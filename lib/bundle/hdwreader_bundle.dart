import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../models/wiki_models.dart';

/// A fully offline .hdwreader bundle exported from the deepwiki-open web app
/// (see api/api.py::generate_hdwreader_export). Exposes the same
/// WikiStructure/VulnReport/WebVulnReport shapes the server client layer
/// does, so screens don't need to know whether their data came from a live
/// endpoint or a local file.
class HdwReaderBundle {
  final Map<String, dynamic> manifest;
  final WikiStructure structure;
  final VulnReport? vulnReport;
  final WebVulnReport? webVulnReport;

  const HdwReaderBundle({
    required this.manifest,
    required this.structure,
    this.vulnReport,
    this.webVulnReport,
  });

  String get title => manifest['title'] as String? ?? 'Untitled wiki';
  String get repoUrl => manifest['repo_url'] as String? ?? '';
  String get repoType => manifest['repo_type'] as String? ?? '';
  String get owner => manifest['owner'] as String? ?? '';
  String get repo => manifest['repo'] as String? ?? '';
  String get language => manifest['language'] as String? ?? 'en';

  static Future<HdwReaderBundle> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return parse(bytes);
  }

  static HdwReaderBundle parse(List<int> zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    Map<String, dynamic>? manifestJson;
    final pageContents = <String, String>{}; // page id -> markdown content
    Map<String, dynamic>? vulnJson;
    Map<String, dynamic>? webVulnJson;

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      final content = file.content as List<int>;
      if (name == 'manifest.json') {
        manifestJson = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      } else if (name.startsWith('pages/') && name.endsWith('.md')) {
        final id = name.substring('pages/'.length, name.length - '.md'.length);
        pageContents[id] = utf8.decode(content);
      } else if (name == 'security/vuln_report.json') {
        vulnJson = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      } else if (name == 'security/web_vuln_report.json') {
        webVulnJson = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      }
    }

    if (manifestJson == null) {
      throw const FormatException('Not a valid .hdwreader bundle: manifest.json missing');
    }

    final sections = (manifestJson['sections'] as List? ?? [])
        .map((e) => WikiSection.fromJson(e as Map<String, dynamic>))
        .toList();
    final rootSections = (manifestJson['root_sections'] as List? ?? []).map((e) => e as String).toList();
    final pages = (manifestJson['pages'] as List? ?? []).map((e) {
      final pageJson = e as Map<String, dynamic>;
      final id = pageJson['id'] as String;
      return WikiPage.fromJson(pageJson, content: pageContents[id] ?? '');
    }).toList();

    final structure = WikiStructure(
      id: (manifestJson['repo'] as String?) ?? 'wiki',
      title: manifestJson['title'] as String? ?? 'Untitled wiki',
      description: manifestJson['description'] as String? ?? '',
      pages: pages,
      sections: sections,
      rootSections: rootSections,
    );

    return HdwReaderBundle(
      manifest: manifestJson,
      structure: structure,
      vulnReport: vulnJson != null ? VulnReport.fromJson(vulnJson) : null,
      webVulnReport: webVulnJson != null ? WebVulnReport.fromJson(webVulnJson) : null,
    );
  }
}
