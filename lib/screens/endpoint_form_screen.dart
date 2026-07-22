import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/endpoint.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class EndpointFormScreen extends StatefulWidget {
  final Endpoint? existing;
  const EndpointFormScreen({super.key, this.existing});

  @override
  State<EndpointFormScreen> createState() => _EndpointFormScreenState();
}

class _EndpointFormScreenState extends State<EndpointFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _urlController = TextEditingController(text: widget.existing?.baseUrl ?? 'http://');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit server' : 'Add server')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Home server'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://192.168.1.50:8001',
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'Enter a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Text(
                'The base URL of a running HackDeepWiki backend (the FastAPI port -- 8001 by default).',
                style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.muted),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEditing ? 'Save' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final library = context.read<LibraryProvider>();
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (widget.existing != null) {
      await library.updateEndpoint(widget.existing!.copyWith(name: name, baseUrl: url));
    } else {
      await library.addEndpoint(name, url);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
