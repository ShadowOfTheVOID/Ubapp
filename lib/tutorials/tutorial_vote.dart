/// Pure majority-wins yes/no vote used to decide whether a game's
/// pre-game tutorial should be shown. Engines and servers wrap this;
/// it has no I/O of its own.
class TutorialVote {
  bool _open = false;
  final Map<String, bool> _votes = {};
  bool? _result;
  bool _shown = false;

  bool get isOpen => _open;
  bool get hasResult => _result != null;
  bool? get result => _result;

  /// Tutorial was actually displayed to players — used to keep the
  /// vote button hidden after the tutorial has already run once.
  bool get tutorialShown => _shown;
  void markShown() => _shown = true;

  Map<String, bool> get votes => Map.unmodifiable(_votes);

  int get yesCount => _votes.values.where((v) => v).length;
  int get noCount => _votes.values.where((v) => !v).length;

  /// Reset and open a fresh vote. [eligibleIds] is the snapshot of
  /// players in the lobby at the moment the vote was called.
  void open(Iterable<String> eligibleIds) {
    _open = true;
    _votes.clear();
    _result = null;
    _eligible
      ..clear()
      ..addAll(eligibleIds);
  }

  final Set<String> _eligible = {};
  Iterable<String> get eligible => _eligible;
  bool isEligible(String id) => _eligible.contains(id);
  int get eligibleCount => _eligible.length;

  /// Submit a vote. Returns true once every eligible voter has
  /// submitted — at which point [result] is finalized.
  bool submit(String voterId, bool yes) {
    if (!_open) return false;
    if (!_eligible.contains(voterId)) return false;
    _votes[voterId] = yes;
    if (_votes.length >= _eligible.length) {
      _finalize();
      return true;
    }
    return false;
  }

  /// Force-close the vote with the votes collected so far.
  void close() {
    if (!_open) return;
    _finalize();
  }

  /// A voter dropped out (e.g. left the lobby). Removes them from
  /// eligibility and the tally; finalizes if everyone still in has voted.
  void removeVoter(String id) {
    if (!_open) return;
    _eligible.remove(id);
    _votes.remove(id);
    if (_eligible.isEmpty) {
      _open = false;
      _votes.clear();
      _result = null;
      return;
    }
    if (_votes.length >= _eligible.length) {
      _finalize();
    }
  }

  void _finalize() {
    final yes = yesCount;
    final no = noCount;
    // Strict majority — ties resolve to "no" (skip tutorial).
    _result = yes > no;
    _open = false;
  }
}
