/// Batch-runs journal actions through the engine, dropping individual lines the
/// engine rejects instead of losing the rest of the batch.
library;

/// Run journal actions `[from, to)` through `run` (which submits one script string and returns
/// the engine's error, or null on success), skipping any line the engine rejects.
///
/// `Session::run_script` executes statements up to the first failing line and reports it as
/// `line N: … [line]` (N 1-based within the submitted script), so recovery is **resume after
/// line N — never retry the batch**, which would double-apply the lines that already ran. The
/// skip unit is the whole journal line: a multi-statement line (`a; b`) that fails on `b` has
/// already executed `a`, so neither re-running nor finishing it is safe. Journal actions are
/// guaranteed single-line by the recorder (embedded newlines split into continuation records),
/// which makes the line↔action mapping exact.
///
/// Net effect: an unknown verb from a journal recorded by a newer app version degrades to a
/// one-line drop (divergent pixels) instead of silently discarding the remainder of an
/// up-to-2000-action batch (docs/aa-brush/DESIGN.md companion fix #2). Forward replay — an old
/// app replaying a newer journal — was never guaranteed; this just makes its failure mode sane.
///
/// Returns the number of lines skipped. `onSkip` receives one loggable message per skipped
/// line (and one final message if an error can't be mapped to a line, in which case the rest
/// of the batch is abandoned exactly as before this fix).
int runActionsSkippingBad(
  String? Function(String script) run,
  List<String> actions,
  int from,
  int to, {
  void Function(String message)? onSkip,
}) {
  var skipped = 0;
  var pos = from;
  while (pos < to) {
    final err = run(actions.sublist(pos, to).join('\n'));
    if (err == null) return skipped;
    final m = RegExp(r'^line (\d+):').firstMatch(err);
    final n = m == null ? null : int.tryParse(m.group(1)!);
    if (n == null || n < 1 || pos + n > to) {
      // No usable line number — abandon the remainder of this batch (the pre-fix behavior).
      onSkip?.call('replay: unrecoverable script error at $pos..$to: $err');
      return skipped;
    }
    // Lines [pos, pos + n - 1) already executed inside the engine; line pos + n - 1 is the
    // offender and is dropped; resume with the line after it.
    onSkip?.call('replay: skipping action ${pos + n - 1}: $err');
    skipped++;
    pos += n;
  }
  return skipped;
}
