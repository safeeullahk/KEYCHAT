import 'package:flutter/material.dart';

import '../services/chat_api.dart';
import '../services/settings_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.initial,
  });

  final SettingsStore store;
  final AppSettings initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ChatApi _api = ChatApi();
  final TextEditingController _apiKey = TextEditingController();
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _profileName;

  late AppSettings _settings;
  bool _obscureKey = true;
  bool _saving = false;
  bool _loadingModels = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    final active = _settings.activeProfile;
    _baseUrl = TextEditingController(text: active.baseUrl);
    _model = TextEditingController(text: active.model);
    _profileName = TextEditingController(text: active.name);
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _profileName.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _keyForRequest() async {
    final typed = _apiKey.text.trim();
    if (typed.isNotEmpty) return typed;
    return widget.store.readApiKey();
  }

  String? _validateBaseUrl(String? value) {
    final url = normalizeBaseUrl(value ?? '');
    if (url.isEmpty) return 'Enter the API base URL.';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Use a full URL, e.g. https://api.openai.com/v1';
    }
    return null;
  }

  void _selectProfile(ApiProfile profile) {
    setState(() {
      _settings = _settings.copyWith(activeProfileId: profile.id);
      _baseUrl.text = profile.baseUrl;
      _model.text = profile.model;
      _profileName.text = profile.name;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final typedKey = _apiKey.text.trim();
    if (typedKey.isNotEmpty) {
      await widget.store.saveApiKey(typedKey);
    }

    final baseUrl = normalizeBaseUrl(_baseUrl.text);
    final model = _model.text.trim();
    final name = _profileName.text.trim().isEmpty
        ? 'Profile ${_settings.profiles.length}'
        : _profileName.text.trim();

    final updatedProfiles = _settings.profiles.map((p) {
      if (p.id == _settings.activeProfile.id) {
        return p.copyWith(name: name, baseUrl: baseUrl, model: model);
      }
      return p;
    }).toList();

    final updated = await widget.store.saveProfiles(
      profiles: updatedProfiles,
      activeProfileId: _settings.activeProfile.id,
      hasApiKey: typedKey.isNotEmpty || _settings.hasApiKey,
    );

    if (!mounted) return;
    Navigator.of(context).pop(updated);
  }

  Future<void> _addProfile() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newProfile = ApiProfile(
      id: id,
      name: 'Profile ${_settings.profiles.length + 1}',
      baseUrl: SettingsStore.defaultBaseUrl,
      model: SettingsStore.defaultModel,
    );
    final profiles = [..._settings.profiles, newProfile];
    final updated = await widget.store.saveProfiles(
      profiles: profiles,
      activeProfileId: id,
      hasApiKey: _settings.hasApiKey,
    );
    if (!mounted) return;
    setState(() => _settings = updated);
    _selectProfile(newProfile);
    _showMessage('Added a new profile. Set its endpoint/model and save.');
  }

  Future<void> _removeCurrentProfile() async {
    if (_settings.profiles.length <= 1) {
      _showMessage('Keep at least one profile.');
      return;
    }
    final current = _settings.activeProfile;
    final profiles =
        _settings.profiles.where((p) => p.id != current.id).toList();
    final updated = await widget.store.saveProfiles(
      profiles: profiles,
      activeProfileId: profiles.first.id,
      hasApiKey: _settings.hasApiKey,
    );
    if (!mounted) return;
    setState(() => _settings = updated);
    _selectProfile(updated.activeProfile);
  }

  Future<void> _loadModels() async {
    final baseUrl = normalizeBaseUrl(_baseUrl.text);
    if (_validateBaseUrl(baseUrl) != null) {
      _showMessage('Enter a valid base URL first.');
      return;
    }
    final apiKey = await _keyForRequest();
    if (!mounted) return;
    if (apiKey == null) {
      _showMessage('Enter your API key first.');
      return;
    }

    setState(() => _loadingModels = true);
    try {
      final models = await _api.listModels(baseUrl: baseUrl, apiKey: apiKey);
      if (!mounted) return;
      if (models.isEmpty) {
        _showMessage('That endpoint did not return any models.');
        return;
      }
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      '${models.length} models',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: models.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    title: Text(models[index]),
                    onTap: () => Navigator.of(context).pop(models[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (picked != null && mounted) {
        setState(() => _model.text = picked);
      }
    } on ChatApiException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Could not load models: $error');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.titleSmall?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Models & API Keys'),
        actions: [
          IconButton(
            tooltip: 'Add profile',
            onPressed: _addProfile,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('Profiles (as many APIs/models as you want)',
                    style: labelStyle),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final profile in _settings.profiles)
                      ChoiceChip(
                        label: Text(profile.name),
                        selected: profile.id == _settings.activeProfile.id,
                        onSelected: (_) => _selectProfile(profile),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _settings.profiles.length > 1
                        ? _removeCurrentProfile
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove current profile'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Profile', style: labelStyle),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _profileName,
                  decoration: const InputDecoration(
                    labelText: 'Profile name',
                    hintText: 'e.g. OpenAI GPT, Groq Llama, Local',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Your API key', style: labelStyle),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _apiKey,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    hintText: _settings.hasApiKey ? 'A key is saved' : 'sk-…',
                    helperText: _settings.hasApiKey
                        ? 'Leave blank to keep the saved key on this device.'
                        : 'Paste any compatible API key. Kept in this device\'s secure keystore.',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      tooltip: _obscureKey ? 'Show key' : 'Hide key',
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty && !_settings.hasApiKey) {
                      return 'Enter your API key.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Text('Endpoint', style: labelStyle),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _baseUrl,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    helperText:
                        'Any OpenAI-compatible API (OpenAI, OpenRouter, Groq, local /v1, etc.).',
                    helperMaxLines: 2,
                  ),
                  validator: _validateBaseUrl,
                ),
                const SizedBox(height: 20),
                Text('Model', style: labelStyle),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _model,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Model name',
                    hintText: SettingsStore.defaultModel,
                    helperText:
                        'Leave empty? Not recommended. Pick any model your key can access.',
                    helperMaxLines: 2,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter the model name.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _loadingModels ? null : _loadModels,
                    icon: _loadingModels
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.list_alt_rounded, size: 18),
                    label: const Text('Load models from this endpoint'),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save profile'),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your key stays in this device\'s secure keystore. '
                        'Requests go only to the endpoint you configure.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
