part of 'assistant_settings_edit_page.dart';

class _CustomRequestTab extends StatefulWidget {
  const _CustomRequestTab({required this.assistantId});
  final String assistantId;

  @override
  State<_CustomRequestTab> createState() => _CustomRequestTabState();
}

class _CustomRequestTabState extends State<_CustomRequestTab> {
  String? _loadedAssistantId;
  AssistantProvider? _provider;
  final List<Map<String, String>> _headerDrafts = <Map<String, String>>[];
  final List<Map<String, String>> _bodyDrafts = <Map<String, String>>[];

  bool _loadDrafts(Assistant assistant) {
    if (_loadedAssistantId == assistant.id) return false;
    _loadedAssistantId = assistant.id;
    _headerDrafts
      ..clear()
      ..addAll(assistant.customHeaders.map(Map<String, String>.from));
    _bodyDrafts
      ..clear()
      ..addAll(assistant.customBody.map(Map<String, String>.from));
    return true;
  }

  List<Map<String, String>> _persistableHeaders() => <Map<String, String>>[
    for (final entry in _headerDrafts)
      if ((entry['name'] ?? '').trim().isNotEmpty &&
          !BaiziGateway.isProtectedHeader(entry['name'] ?? ''))
        <String, String>{
          'name': entry['name']!.trim(),
          'value': entry['value'] ?? '',
        },
  ];

  List<Map<String, String>> _persistableBody() => <Map<String, String>>[
    for (final entry in _bodyDrafts)
      if ((entry['key'] ?? '').trim().isNotEmpty &&
          !BaiziGateway.isProtectedBodyField(entry['key'] ?? ''))
        <String, String>{
          'key': entry['key']!.trim(),
          'value': entry['value'] ?? '',
        },
  ];

  bool _sameEntries(
    List<Map<String, String>> current,
    List<Map<String, String>> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].length != next[i].length) return false;
      for (final entry in current[i].entries) {
        if (next[i][entry.key] != entry.value) return false;
      }
    }
    return true;
  }

  void _persistHeaders(AssistantProvider provider) {
    final assistant = provider.getById(widget.assistantId);
    if (assistant == null) return;
    final next = _persistableHeaders();
    if (_sameEntries(assistant.customHeaders, next)) return;
    unawaited(
      provider.updateAssistant(assistant.copyWith(customHeaders: next)),
    );
  }

  void _persistBody(AssistantProvider provider) {
    final assistant = provider.getById(widget.assistantId);
    if (assistant == null) return;
    final next = _persistableBody();
    if (_sameEntries(assistant.customBody, next)) return;
    unawaited(provider.updateAssistant(assistant.copyWith(customBody: next)));
  }

  @override
  void dispose() {
    final provider = _provider;
    if (provider != null) {
      _persistHeaders(provider);
      _persistBody(provider);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ap = context.watch<AssistantProvider>();
    _provider = ap;
    final a = ap.getById(widget.assistantId)!;
    final loadedDrafts = _loadDrafts(a);
    if (loadedDrafts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _persistHeaders(ap);
        _persistBody(ap);
      });
    }

    Widget card({required Widget child}) => Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        20,
        8,
      ), // Increased right padding
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
          boxShadow: isDark ? [] : AppShadows.soft,
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );

    void addHeader() {
      setState(
        () => _headerDrafts.add(<String, String>{'name': '', 'value': ''}),
      );
    }

    void removeHeader(int index) {
      if (index >= 0 && index < _headerDrafts.length) {
        setState(() => _headerDrafts.removeAt(index));
        _persistHeaders(ap);
      }
    }

    void updateHeader(int index, {String? name, String? value}) {
      if (index >= 0 && index < _headerDrafts.length) {
        final cur = Map<String, String>.from(_headerDrafts[index]);
        if (name != null) cur['name'] = name;
        if (value != null) cur['value'] = value;
        _headerDrafts[index] = cur;
      }
    }

    void addBody() {
      setState(() => _bodyDrafts.add(<String, String>{'key': '', 'value': ''}));
    }

    void removeBody(int index) {
      if (index >= 0 && index < _bodyDrafts.length) {
        setState(() => _bodyDrafts.removeAt(index));
        _persistBody(ap);
      }
    }

    void updateBody(int index, {String? key, String? value}) {
      if (index >= 0 && index < _bodyDrafts.length) {
        final cur = Map<String, String>.from(_bodyDrafts[index]);
        if (key != null) cur['key'] = key;
        if (value != null) cur['value'] = value;
        _bodyDrafts[index] = cur;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16), // Reduced top padding
      children: [
        // Headers
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.assistantEditCustomHeadersTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _TactileRow(
                      onTap: addHeader,
                      pressedScale: 0.97,
                      builder: (pressed) {
                        final color = pressed
                            ? cs.primary.withValues(alpha: 0.7)
                            : cs.primary;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Lucide.Plus, size: 16, color: color),
                            const SizedBox(width: 4),
                            Text(
                              l10n.assistantEditCustomHeadersAdd,
                              style: TextStyle(
                                color: color,
                                fontWeight: AppFontWeights.semibold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _headerDrafts.length; i++) ...[
                _HeaderRow(
                  index: i,
                  name: _headerDrafts[i]['name'] ?? '',
                  value: _headerDrafts[i]['value'] ?? '',
                  onChanged: (k, v) => updateHeader(i, name: k, value: v),
                  onCommit: () => _persistHeaders(ap),
                  onDelete: () => removeHeader(i),
                ),
                const SizedBox(height: 10),
              ],
              if (_headerDrafts.isEmpty)
                Text(
                  l10n.assistantEditCustomHeadersEmpty,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),

        // Body
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.assistantEditCustomBodyTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _TactileRow(
                      onTap: addBody,
                      pressedScale: 0.97,
                      builder: (pressed) {
                        final color = pressed
                            ? cs.primary.withValues(alpha: 0.7)
                            : cs.primary;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Lucide.Plus, size: 16, color: color),
                            const SizedBox(width: 4),
                            Text(
                              l10n.assistantEditCustomBodyAdd,
                              style: TextStyle(
                                color: color,
                                fontWeight: AppFontWeights.semibold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _bodyDrafts.length; i++) ...[
                _BodyRow(
                  index: i,
                  keyName: _bodyDrafts[i]['key'] ?? '',
                  value: _bodyDrafts[i]['value'] ?? '',
                  onChanged: (k, v) => updateBody(i, key: k, value: v),
                  onCommit: () => _persistBody(ap),
                  onDelete: () => removeBody(i),
                ),
                const SizedBox(height: 10),
              ],
              if (_bodyDrafts.isEmpty)
                Text(
                  l10n.assistantEditCustomBodyEmpty,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatefulWidget {
  const _HeaderRow({
    required this.index,
    required this.name,
    required this.value,
    required this.onChanged,
    required this.onCommit,
    required this.onDelete,
  });
  final int index;
  final String name;
  final String value;
  final void Function(String name, String value) onChanged;
  final VoidCallback onCommit;
  final VoidCallback onDelete;

  @override
  State<_HeaderRow> createState() => _HeaderRowState();
}

class _HeaderRowState extends State<_HeaderRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _valFocus;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
    _valCtrl = TextEditingController(text: widget.value);
    _nameFocus = FocusNode();
    _valFocus = FocusNode();
    _nameFocus.addListener(_handleFocusChanged);
    _valFocus.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (!_nameFocus.hasFocus && !_valFocus.hasFocus) widget.onCommit();
  }

  @override
  void didUpdateWidget(covariant _HeaderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Avoid resetting controller text while the field is focused to prevent cursor jump.
    if (oldWidget.name != widget.name && !_nameFocus.hasFocus) {
      _nameCtrl.text = widget.name;
    }
    if (oldWidget.value != widget.value && !_valFocus.hasFocus) {
      _valCtrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valCtrl.dispose();
    _nameFocus.dispose();
    _valFocus.dispose();
    super.dispose();
  }

  InputDecoration _dec(
    BuildContext context,
    String label, {
    String? errorText,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      filled: true,
      fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final protected = BaiziGateway.isProtectedHeader(_nameCtrl.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                decoration: _dec(
                  context,
                  l10n.assistantEditHeaderNameLabel,
                  errorText: protected
                      ? l10n.assistantEditProtectedRequestFieldError
                      : null,
                ),
                onChanged: (v) {
                  setState(() {});
                  widget.onChanged(v, _valCtrl.text);
                },
                onSubmitted: (_) => widget.onCommit(),
              ),
            ),
            const SizedBox(width: 8),
            _TactileIconButton(
              icon: Lucide.Trash2,
              color: cs.error,
              size: 20,
              onTap: widget.onDelete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _valCtrl,
          focusNode: _valFocus,
          textInputAction: TextInputAction.done,
          decoration: _dec(context, l10n.assistantEditHeaderValueLabel),
          onChanged: (v) => widget.onChanged(_nameCtrl.text, v),
          onSubmitted: (_) => widget.onCommit(),
        ),
      ],
    );
  }
}

class _BodyRow extends StatefulWidget {
  const _BodyRow({
    required this.index,
    required this.keyName,
    required this.value,
    required this.onChanged,
    required this.onCommit,
    required this.onDelete,
  });
  final int index;
  final String keyName;
  final String value;
  final void Function(String key, String value) onChanged;
  final VoidCallback onCommit;
  final VoidCallback onDelete;

  @override
  State<_BodyRow> createState() => _BodyRowState();
}

class _BodyRowState extends State<_BodyRow> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valCtrl;
  late final FocusNode _keyFocus;
  late final FocusNode _valFocus;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.keyName);
    _valCtrl = TextEditingController(text: widget.value);
    _keyFocus = FocusNode();
    _valFocus = FocusNode();
    _keyFocus.addListener(_handleFocusChanged);
    _valFocus.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (!_keyFocus.hasFocus && !_valFocus.hasFocus) widget.onCommit();
  }

  @override
  void didUpdateWidget(covariant _BodyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Avoid resetting controller text while the field is focused to prevent cursor jump.
    if (oldWidget.keyName != widget.keyName && !_keyFocus.hasFocus) {
      _keyCtrl.text = widget.keyName;
    }
    if (oldWidget.value != widget.value && !_valFocus.hasFocus) {
      _valCtrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    _keyFocus.dispose();
    _valFocus.dispose();
    super.dispose();
  }

  InputDecoration _dec(
    BuildContext context,
    String label, {
    String? errorText,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      filled: true,
      fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
      ),
      alignLabelWithHint: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final protected = BaiziGateway.isProtectedBodyField(_keyCtrl.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _keyCtrl,
                focusNode: _keyFocus,
                textInputAction: TextInputAction.next,
                decoration: _dec(
                  context,
                  l10n.assistantEditBodyKeyLabel,
                  errorText: protected
                      ? l10n.assistantEditProtectedRequestFieldError
                      : null,
                ),
                onChanged: (v) {
                  setState(() {});
                  widget.onChanged(v, _valCtrl.text);
                },
                onSubmitted: (_) => widget.onCommit(),
              ),
            ),
            const SizedBox(width: 8),
            _TactileIconButton(
              icon: Lucide.Trash2,
              color: cs.error,
              size: 20,
              onTap: widget.onDelete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _valCtrl,
          focusNode: _valFocus,
          minLines: 3,
          maxLines: 6,
          decoration: _dec(context, l10n.assistantEditBodyValueLabel),
          onChanged: (v) => widget.onChanged(_keyCtrl.text, v),
        ),
      ],
    );
  }
}
