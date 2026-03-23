import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/chat/providers/chat_search_providers.dart';
import 'package:prism_plurality/features/chat/widgets/search_result_tile.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    // Trigger rebuild so clear button visibility updates immediately.
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _debounce?.cancel();
    _controller.dispose();
    // Reset query so returning to search starts fresh.
    ref.read(chatSearchQueryProvider.notifier).set('');
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(chatSearchQueryProvider.notifier).set(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = ref.watch(chatSearchQueryProvider);
    final resultsAsync = ref.watch(chatSearchResultsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    PrismGlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      iconSize: 18,
                      onPressed: () => context.pop(),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TintedGlassSurface(
                        borderRadius: BorderRadius.circular(16),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 20,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Search messages...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  hintStyle:
                                      theme.textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                style: theme.textTheme.bodyLarge,
                                onChanged: _onQueryChanged,
                              ),
                            ),
                            if (_controller.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _controller.clear();
                                  ref
                                      .read(chatSearchQueryProvider.notifier)
                                      .set('');
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Body
          if (query.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Find messages across your conversations',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (query.length < 2)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Keep typing to search...',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            resultsAsync.when(
              data: (results) {
                if (results.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No messages found for '$query'",
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try fewer or different words',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverList.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return SearchResultTile(
                      result: result,
                      onTap: () {
                        context.go(
                          '${AppRoutePaths.chatConversation(result.conversationId)}'
                          '?messageId=${result.messageId}',
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error: $error')),
              ),
            ),
        ],
      ),
    );
  }
}
