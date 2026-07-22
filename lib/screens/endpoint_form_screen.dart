import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/endpoint.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

/// Address + port are collected as two separate fields on purpose: a
/// HackDeepWiki install actually has TWO ports -- the browser/web UI port
/// (3000 by default) and the API port the FastAPI backend serves on (8001
/// by default, printed in the console at startup). This app needs the API
/// port specifically (it's a native client, not a browser, so it always
/// talks to the backend directly) -- a single "Server URL" field led users
/// to paste in the browser URL (port 3000) and hit a confusing connection
/// error, since nothing this app needs is actually served there.
class EndpointFormScreen extends StatefulWidget {
  final Endpoint? existing;
  const EndpointFormScreen({super.key, this.existing});

  @override
  State<EndpointFormScreen> createState() => _EndpointFormScreenState();
}

class _EndpointFormScreenState extends State<EndpointFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _portController;
  bool _useHttps = false;
  bool _saving = false;
  String? _testError;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _addressController = TextEditingController(text: existing?.host ?? '127.0.0.1');
    _portController = TextEditingController(text: (existing?.port ?? 8001).toString());
    _useHttps = existing?.scheme == 'https';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final colors = Theme.of(context).appColors;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit server' : 'Add server')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Home server'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: '127.0.0.1 or 192.168.1.50',
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(labelText: 'API port', hintText: '8001'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 1 || n > 65535) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                value: _useHttps,
                onChanged: (v) => setState(() => _useHttps = v ?? false),
                title: const Text('Use HTTPS'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colors.inputBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠️ Not the browser port', style: TextStyle(fontWeight: FontWeight.w600, color: colors.foreground)),
                    const SizedBox(height: 4),
                    Text(
                      'This is the API port -- printed in the terminal where HackDeepWiki '
                      'was started ("Starting FastAPI backend on port ..."), 8001 by default. '
                      "It is NOT the port you open in your browser (usually 3000) -- this app "
                      "talks to the backend directly and can't reach anything on the browser port.",
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ),
              ),
              if (_testOk != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(_testOk! ? Icons.check_circle : Icons.error, color: _testOk! ? Colors.green : colors.highlight, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testOk! ? 'Connected successfully.' : (_testError ?? 'Could not connect.'),
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
                      onPressed: _saving ? null : _testConnection,
                      child: const Text('Test connection'),
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

  Endpoint? _buildEndpoint() {
    if (!_formKey.currentState!.validate()) return null;
    final baseUrl = Endpoint.buildBaseUrl(
      scheme: _useHttps ? 'https' : 'http',
      host: _addressController.text.trim(),
      port: int.parse(_portController.text.trim()),
    );
    return (widget.existing ?? const Endpoint(id: '', name: '', baseUrl: '')).copyWith(
      name: _nameController.text.trim(),
      baseUrl: baseUrl,
    );
  }

  Future<void> _testConnection() async {
    final draft = _buildEndpoint();
    if (draft == null) return;
    setState(() {
      _saving = true;
      _testOk = null;
      _testError = null;
    });
    final library = context.read<LibraryProvider>();
    final ok = await library.testConnectionFor(draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _testOk = ok;
      _testError = ok
          ? null
          : 'Could not reach $_addressController.text:$_portController.text. Double-check the '
              'address and API port (see the note above), and that HackDeepWiki is running.';
    });
  }

  Future<void> _save() async {
    final draft = _buildEndpoint();
    if (draft == null) return;
    setState(() => _saving = true);
    final library = context.read<LibraryProvider>();
    if (widget.existing != null) {
      await library.updateEndpoint(draft);
    } else {
      await library.addEndpoint(draft.name, draft.baseUrl);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
