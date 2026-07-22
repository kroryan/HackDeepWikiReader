import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../llm/llm_client.dart';
import '../models/chat_models.dart';
import '../models/llm_config.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// Add/edit one LLM connection. The "preset" only picks sensible defaults
/// (base URL, whether an API key is needed) -- under the hood every preset
/// maps to one of the three wire protocols this app implements natively
/// (see lib/llm/): Ollama, OpenAI-compatible (covers both "ChatGPT" and any
/// custom OpenAI-compatible endpoint), Anthropic Claude.
class LlmConnectionFormScreen extends StatefulWidget {
  final LlmConnection? existing;
  const LlmConnectionFormScreen({super.key, this.existing});

  @override
  State<LlmConnectionFormScreen> createState() => _LlmConnectionFormScreenState();
}

class _LlmConnectionFormScreenState extends State<LlmConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late LlmPreset _preset;
  bool _saving = false;
  bool _testing = false;
  String? _testError;
  bool? _testOk;
  bool _obscureKey = true;
  bool _refreshingModels = false;
  String? _refreshError;
  List<String> _availableModels = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _preset = existing?.preset ?? LlmPreset.ollama;
    _nameController = TextEditingController(text: existing?.name ?? _preset.label);
    _baseUrlController = TextEditingController(text: existing?.baseUrl ?? _preset.defaultBaseUrl ?? '');
    _apiKeyController = TextEditingController(text: existing?.apiKey ?? '');
    _modelController = TextEditingController(text: existing?.model ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _onPresetChanged(LlmPreset? value) {
    if (value == null) return;
    setState(() {
      final wasDefaultName = _nameController.text == _preset.label;
      _preset = value;
      if (wasDefaultName) _nameController.text = _preset.label;
      if (_baseUrlController.text.isEmpty || _baseUrlController.text == _preset.defaultBaseUrl) {
        _baseUrlController.text = _preset.defaultBaseUrl ?? '';
      }
      _testOk = null;
      _testError = null;
      _availableModels = [];
      _refreshError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final colors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit provider' : 'Add provider')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<LlmPreset>(
                value: _preset,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final preset in LlmPreset.values)
                    DropdownMenuItem(value: preset, child: Text(preset.label)),
                ],
                onChanged: _onPresetChanged,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: _preset == LlmPreset.ollama ? 'http://127.0.0.1:11434' : 'https://…',
                ),
                keyboardType: TextInputType.url,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              if (_preset.needsApiKey) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: _preset == LlmPreset.anthropic ? 'API key / subscription token' : 'API key',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  obscureText: _obscureKey,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(labelText: 'Model', hintText: _preset.modelHint),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _refreshingModels ? null : _refreshModels,
                  icon: _refreshingModels
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh models'),
                ),
              ),
              if (_refreshError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_refreshError!, style: TextStyle(color: colors.highlight, fontSize: 12)),
                ),
              if (_availableModels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final m in _availableModels)
                        ChoiceChip(
                          label: Text(m, overflow: TextOverflow.ellipsis),
                          selected: _modelController.text == m,
                          onSelected: (_) => setState(() => _modelController.text = m),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (_testOk != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(_testOk! ? Icons.check_circle : Icons.error,
                          color: _testOk! ? Colors.green : colors.highlight, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testOk! ? 'Provider responded successfully.' : (_testError ?? 'Test failed.'),
                          style: TextStyle(color: _testOk! ? Colors.green : colors.highlight, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testing ? null : _testConnection,
                      child: _testing
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Test'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isEditing ? 'Save' : 'Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  LlmConnection _draft() => (widget.existing ??
          LlmConnection(id: '', name: '', kind: _preset.kind, preset: _preset, baseUrl: '', model: ''))
      .copyWith(
    name: _nameController.text.trim(),
    kind: _preset.kind,
    preset: _preset,
    baseUrl: _baseUrlController.text.trim(),
    apiKey: _apiKeyController.text.trim().isEmpty ? null : _apiKeyController.text.trim(),
    model: _modelController.text.trim(),
  );

  /// Fetches whatever models the endpoint/credentials currently in the form
  /// can serve (Ollama: /api/tags, OpenAI-compatible: /models, Anthropic:
  /// /models) so the user can pick one instead of needing to already know a
  /// valid model id -- same idea as HackDeepWiki's own provider setup. If
  /// this isn't used at all (endpoint doesn't support it, or the user just
  /// skips it), the Model field above stays a plain, always-editable text
  /// field, so typing one by hand is never blocked on this working.
  Future<void> _refreshModels() async {
    if (_baseUrlController.text.trim().isEmpty) {
      setState(() => _refreshError = 'Enter a base URL first.');
      return;
    }
    if (_preset.needsApiKey && _apiKeyController.text.trim().isEmpty) {
      setState(() => _refreshError = 'Enter an API key first.');
      return;
    }
    setState(() {
      _refreshingModels = true;
      _refreshError = null;
      _availableModels = [];
    });
    try {
      final client = buildLlmClientFromFields(
        kind: _preset.kind,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim().isEmpty ? null : _apiKeyController.text.trim(),
      );
      final models = await client.listModels().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _refreshingModels = false;
        _availableModels = models;
        if (models.isEmpty) _refreshError = 'This endpoint reported no models.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _refreshingModels = false;
        _refreshError = e is LlmClientException ? e.message : e.toString();
      });
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testOk = null;
      _testError = null;
    });
    try {
      final client = buildLlmClient(_draft());
      var gotAny = false;
      await client
          .streamChat(systemPrompt: null, messages: const [ChatMessage(role: 'user', content: 'Say OK.')])
          .timeout(const Duration(seconds: 20))
          .forEach((delta) => gotAny = gotAny || delta.isNotEmpty);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        if (!gotAny) _testOk = true; // empty-but-successful stream still means the provider answered
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testError = e is LlmClientException ? e.message : e.toString();
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final settings = context.read<SettingsProvider>();
    if (widget.existing != null) {
      await settings.updateConnection(_draft());
    } else {
      await settings.addConnection(
        name: _nameController.text.trim(),
        preset: _preset,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim().isEmpty ? null : _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}
