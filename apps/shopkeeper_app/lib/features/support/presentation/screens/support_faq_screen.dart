import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../domain/support_models.dart';

/// Searchable help centre.
///
/// The questions come from [supportFaqs] (the support-domain SSOT), so the
/// support hub, this screen and About can never disagree about an answer.
class SupportFaqScreen extends StatefulWidget {
  const SupportFaqScreen({super.key});

  @override
  State<SupportFaqScreen> createState() => _SupportFaqScreenState();
}

class _SupportFaqScreenState extends State<SupportFaqScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _category = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Entries matching BOTH the selected category and the search text.
  List<FaqEntry> get _visible {
    final query = _query.trim().toLowerCase();
    return [
      for (final entry in supportFaqs)
        if ((_category == 'All' || entry.category == _category) &&
            (query.isEmpty || entry.matches(query)))
          entry,
    ];
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonHelpCentre2)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                key: const Key('faq_search_field'),
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: appText(context).commonSearchHelp,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: appText(context).commonClearSearch3,
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final category in ['All', ...faqCategories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) =>
                            setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? _NoResults(query: _query)
                  : ListView(
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      children: [
                        for (final entry in visible)
                          Card(
                            clipBehavior: Clip.antiAlias,
                            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: _FaqTile(entry: entry),
                          ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: FilledButton.tonalIcon(
                            key: const Key('faq_contact_support'),
                            onPressed: () =>
                                context.push(Routes.contactSupport),
                            icon: const Icon(Icons.chat_outlined),
                            label:
                                Text(appText(context).supportFaqScreenStillNeedHelpContactSupport),
                          ),
                        ),
                      ],
                    ),
            ),
            if (visible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  appText(context).supportFaqScreenLengthOfLength2Articles(visible.length, supportFaqs.length),
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One expandable question. Answers stay collapsed so a long list is scannable.
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.entry});

  final FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      title: Text(entry.question, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        entry.category,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            entry.answer,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the search text / category filter matches nothing.
///
/// The shared empty-state component carries the layout; this site owns the
/// wording (a filter that matched nothing is NOT "nothing in this category")
/// and the one action that helps: asking support.
class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return SystemStateView.empty(
      title: query.isEmpty
          ? 'Nothing in this category yet'
          : 'No article matched "$query"',
      message: appText(context).supportFaqScreenTryAnotherWordOrSend,
      icon: Icons.search_off,
      action: FilledButton.tonalIcon(
        onPressed: () => context.push(Routes.contactSupport),
        icon: const Icon(Icons.chat_outlined),
        label: Text(appText(context).commonContactSupport4),
      ),
    );
  }
}