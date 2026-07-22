import 'package:flutter/material.dart';

import '../api/hackdeepwiki_client.dart';
import '../models/endpoint.dart';
import '../models/wiki_models.dart';
import '../providers/wiki_source.dart';
import 'wiki_viewer_screen.dart';

/// Lists every wiki cached on a connected server (GET /api/processed_projects)
/// -- the "browse an endpoint's library" screen.
class ProjectListScreen extends StatefulWidget {
  final Endpoint endpoint;
  const ProjectListScreen({super.key, required this.endpoint});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  late final HackDeepWikiClient _client;
  Future<List<ProcessedProject>>? _future;

  @override
  void initState() {
    super.initState();
    _client = HackDeepWikiClient(widget.endpoint);
    _future = _client.listProcessedProjects();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.endpoint.name)),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _future = _client.listProcessedProjects());
          await _future;
        },
        child: FutureBuilder<List<ProcessedProject>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not reach ${widget.endpoint.baseUrl}:\n${snapshot.error}'),
                ),
              ]);
            }
            final projects = snapshot.data ?? [];
            if (projects.isEmpty) {
              return const Center(child: Text('No wikis found on this server yet.'));
            }
            return ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return ListTile(
                  leading: Icon(project.isWebsite ? Icons.public : Icons.code),
                  title: Text(project.name),
                  subtitle: Text('${project.repoType} · ${project.language}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openWiki(project),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openWiki(ProcessedProject project) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final data = await _client.getWikiCache(
        owner: project.owner,
        repo: project.repo,
        repoType: project.repoType,
        language: project.language,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      if (data == null || data['wiki_structure'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No wiki content found for this project.')),
        );
        return;
      }
      final structureJson = data['wiki_structure'] as Map<String, dynamic>;
      final generatedPages = (data['generated_pages'] as Map<String, dynamic>?) ?? {};
      final pages = (structureJson['pages'] as List? ?? []).map((e) {
        final pageJson = e as Map<String, dynamic>;
        final pageData = generatedPages[pageJson['id']] as Map<String, dynamic>?;
        return WikiPage.fromJson(pageJson, content: pageData?['content'] as String? ?? '');
      }).toList();
      final structure = WikiStructure(
        id: structureJson['id'] as String? ?? project.repo,
        title: structureJson['title'] as String? ?? project.name,
        description: structureJson['description'] as String? ?? '',
        pages: pages,
        sections: (structureJson['sections'] as List? ?? [])
            .map((e) => WikiSection.fromJson(e as Map<String, dynamic>))
            .toList(),
        rootSections: (structureJson['rootSections'] as List? ?? []).map((e) => e as String).toList(),
      );

      final source = ServerWikiSource(
        endpoint: widget.endpoint,
        project: project,
        client: HackDeepWikiClient(widget.endpoint),
        structure: structure,
        wikiCacheData: data,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WikiViewerScreen(source: source)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load wiki: $e')));
    }
  }
}
