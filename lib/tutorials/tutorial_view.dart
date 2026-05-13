import 'package:flutter/material.dart';

import 'tutorial_content.dart';

/// AppBar action that opens the game's tutorial in a dialog. Used by
/// single-device games (no lobby vote) — multiplayer games gate the
/// tutorial behind a majority vote in the lobby instead.
class TutorialAppBarButton extends StatelessWidget {
  const TutorialAppBarButton({super.key, required this.tutorial});

  final GameTutorial tutorial;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'How to play',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: TutorialView(
              tutorial: tutorial,
              onDone: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paginated tutorial widget used on the Flutter host. Browser-tier
/// guests get an equivalent view rendered by their per-game HTML
/// bundle from the same content (broadcast as JSON).
class TutorialView extends StatefulWidget {
  const TutorialView({super.key, required this.tutorial, this.onDone});

  final GameTutorial tutorial;
  final VoidCallback? onDone;

  @override
  State<TutorialView> createState() => _TutorialViewState();
}

class _TutorialViewState extends State<TutorialView> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.tutorial.sections;
    final theme = Theme.of(context);
    final isLast = _page == sections.length - 1;
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.school),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.tutorial.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text('${_page + 1} / ${sections.length}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: sections.length,
                itemBuilder: (_, i) {
                  final s = sections[i];
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.heading, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(s.body, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _page == 0
                      ? null
                      : () => _controller.previousPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          ),
                  child: const Text('Back'),
                ),
                if (!isLast)
                  FilledButton(
                    onPressed: () => _controller.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    ),
                    child: const Text('Next'),
                  )
                else
                  FilledButton(
                    onPressed: widget.onDone,
                    child: const Text("I'm ready"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable "Show tutorial?" yes/no vote prompt used by every game's
/// lobby. The vote tally + result is supplied by the caller from a
/// [TutorialVote] instance; this widget just renders it.
class TutorialVoteCard extends StatelessWidget {
  const TutorialVoteCard({
    super.key,
    required this.isOpen,
    required this.tutorialShown,
    required this.yesCount,
    required this.noCount,
    required this.eligibleCount,
    required this.myVote,
    required this.result,
    required this.onCallVote,
    required this.onVote,
  });

  final bool isOpen;
  final bool tutorialShown;
  final int yesCount;
  final int noCount;
  final int eligibleCount;
  final bool? myVote;
  final bool? result;
  final VoidCallback onCallVote;
  final void Function(bool yes) onVote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!isOpen && result == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.school_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tutorialShown
                      ? 'Tutorial already shown this lobby.'
                      : 'Want a refresher on the rules? Call a vote.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (!tutorialShown)
                FilledButton.tonal(
                  onPressed: onCallVote,
                  child: const Text('Call tutorial vote'),
                ),
            ],
          ),
        ),
      );
    }
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_vote),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Show tutorial first?',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isOpen
                  ? '${yesCount + noCount} / $eligibleCount voted '
                      '($yesCount yes, $noCount no — majority wins)'
                  : result == true
                      ? 'Majority voted YES — tutorial coming up.'
                      : 'Majority voted NO — skipping tutorial.',
              style: theme.textTheme.bodySmall,
            ),
            if (isOpen) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _VoteButton(
                      label: 'Yes',
                      icon: Icons.check,
                      selected: myVote == true,
                      color: Colors.green.shade600,
                      onTap: () => onVote(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VoteButton(
                      label: 'No',
                      icon: Icons.close,
                      selected: myVote == false,
                      color: Colors.red.shade600,
                      onTap: () => onVote(false),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? Colors.white : null),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
