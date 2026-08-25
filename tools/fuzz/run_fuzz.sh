#!/usr/bin/env bash
# WSL-side fuzzing orchestrator (docs/fuzzing/ANALYSIS.md §3; operations: fuzz/README.md).
#
# Invoked by tools/fuzz/fuzz-day.ps1 / fuzz-night.ps1, or by hand from WSL:
#   bash tools/fuzz/run_fuzz.sh --label night --workers 14 --minutes 540 --cmin
#
# Design: /mnt/c is slow for builds, so sources are rsynced into ~/makapix-fuzz on the
# ext4 filesystem, built and fuzzed there, and corpus + crash artifacts + logs are
# synced back into the repo afterwards (also on Ctrl+C). The corpus merges both ways;
# with --cmin it is minimized first and the repo copy is replaced by the minimized set.

set -u

LABEL=adhoc
WORKERS=4
MINUTES=60
CMIN=0
TARGETS="fuzz_load_mkpx fuzz_session_actions"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)   LABEL=$2;   shift 2 ;;
    --workers) WORKERS=$2; shift 2 ;;
    --minutes) MINUTES=$2; shift 2 ;;
    --targets) TARGETS=$2; shift 2 ;;
    --cmin)    CMIN=1;     shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$HOME/makapix-fuzz"
STAMP="$(date +%Y%m%d-%H%M)"

# shellcheck disable=SC1091
source "$HOME/.cargo/env"

echo "== makapix fuzz: label=$LABEL workers=$WORKERS minutes=$MINUTES cmin=$CMIN"
echo "== targets: $TARGETS"
echo "== repo: $REPO"
echo "== work: $WORK"

# ---- Sync sources into the ext4 work tree -------------------------------------------
mkdir -p "$WORK"
rsync -a "$REPO/Cargo.toml" "$REPO/Cargo.lock" "$WORK/"
rsync -a --delete --exclude target "$REPO/crates/" "$WORK/crates/"
rsync -a --delete --exclude target --exclude corpus --exclude artifacts --exclude logs \
  "$REPO/fuzz/" "$WORK/fuzz/"
mkdir -p "$WORK/fuzz/logs" "$WORK/fuzz/artifacts"
# Merge (never delete) repo corpus into the work corpus.
if [[ -d "$REPO/fuzz/corpus" ]]; then
  rsync -a "$REPO/fuzz/corpus/" "$WORK/fuzz/corpus/"
fi
for T in $TARGETS; do mkdir -p "$WORK/fuzz/corpus/$T"; done

# ---- Build (and seed the corpus on first run) ---------------------------------------
cd "$WORK"
echo "== building fuzz targets (nightly)"
if ! cargo +nightly fuzz build 2>&1 | tail -5; then
  echo "!! cargo fuzz build failed" >&2
  exit 2
fi
if [[ -z "$(ls -A "$WORK/fuzz/corpus/fuzz_load_mkpx" 2>/dev/null)" ]]; then
  echo "== corpus empty: generating seeds"
  (cd "$WORK/fuzz" && cargo +nightly run --release --bin make_seeds)
fi

# ---- Run each target for an equal share of the time budget --------------------------
NTARGETS=$(wc -w <<<"$TARGETS")
SECS_PER=$(( MINUTES * 60 / NTARGETS ))
INTERRUPTED=0
FPID=
trap 'INTERRUPTED=1; [[ -n "$FPID" ]] && kill -TERM "$FPID" 2>/dev/null' INT TERM

declare -A BEFORE AFTER CRASH_NEW
for T in $TARGETS; do
  BEFORE[$T]=$(ls "$WORK/fuzz/corpus/$T" 2>/dev/null | wc -l)
  AFTER[$T]=${BEFORE[$T]}
  CRASH_NEW[$T]=""
done

for T in $TARGETS; do
  [[ $INTERRUPTED == 1 ]] && break
  # Loader: rss_limit=512 is the Android-allocator-wall oracle (one load = one input).
  # Actions: the RSS check is process-wide and allocator retention accumulates over
  # thousands of inputs per worker (false oom-* artifacts, 2026-08-25); a high rss cap
  # plus malloc_limit=512 keeps the genuine single-allocation-bomb oracle instead.
  # The loader's max_len must clear the largest boundary seed (a 256x256x16-layer noise
  # document), or libFuzzer silently truncates it out of the corpus. The loader also gets
  # the container dictionary; the actions target's inputs are Arbitrary-decoded, so a
  # byte dictionary means nothing there.
  DICT=()
  TIMEOUT=   # reset per target: a value set for one target must not leak into the next
  case "$T" in
    fuzz_load_mkpx)
      MAXLEN=4194304; RSSLIM=512;  MALLOCLIM=512
      DICT=(-dict=fuzz/mkpx.dict)
      ;;
    # Differential encode+decode: each execution does real VP8L compression and a libwebp
    # decode, so inputs stay small and the timeout is generous.
    fuzz_webp_differential)
      MAXLEN=2048;    RSSLIM=4096; MALLOCLIM=512; TIMEOUT=25
      ;;
    # Import feeds arbitrary bytes to the `image` decoders; a decoded frame can be far
    # larger than its compressed input, so this one needs allocation headroom.
    fuzz_codec_import)
      MAXLEN=65536;   RSSLIM=4096; MALLOCLIM=2048; TIMEOUT=25
      ;;
    *)  MAXLEN=4096;  RSSLIM=4096; MALLOCLIM=512 ;;
  esac
  TIMEOUT=${TIMEOUT:-10}
  ARTIFACTS_BEFORE=$(ls "$WORK/fuzz/artifacts/$T" 2>/dev/null || true)
  LOG="$WORK/fuzz/logs/$STAMP-$LABEL-$T.log"
  echo "== fuzzing $T: $WORKERS workers, $SECS_PER s, max_len=$MAXLEN (log: $(basename "$LOG"))"
  rm -f "$WORK"/fuzz-*.log
  nice -n 19 cargo +nightly fuzz run "$T" "fuzz/corpus/$T" -- \
    -workers="$WORKERS" -jobs="$WORKERS" -max_total_time="$SECS_PER" \
    -rss_limit_mb="$RSSLIM" -malloc_limit_mb="$MALLOCLIM" \
    -timeout="$TIMEOUT" -max_len="$MAXLEN" -print_final_stats=1 "${DICT[@]}" \
    >"$LOG" 2>&1 &
  FPID=$!
  wait "$FPID"
  RC=$?
  FPID=
  # Per-job logs (fuzz-N.log) land in the cwd; fold them into the log directory.
  for J in "$WORK"/fuzz-*.log; do
    [[ -e "$J" ]] && mv "$J" "$WORK/fuzz/logs/$STAMP-$LABEL-$T.$(basename "$J")"
  done
  AFTER[$T]=$(ls "$WORK/fuzz/corpus/$T" 2>/dev/null | wc -l)
  ARTIFACTS_AFTER=$(ls "$WORK/fuzz/artifacts/$T" 2>/dev/null || true)
  CRASH_NEW[$T]=$(comm -13 <(sort <<<"$ARTIFACTS_BEFORE") <(sort <<<"$ARTIFACTS_AFTER"))
  echo "== $T done (exit $RC): corpus ${BEFORE[$T]} -> ${AFTER[$T]}, new artifacts: $(wc -w <<<"${CRASH_NEW[$T]}" | tr -d ' ')"
done

# ---- Optional corpus minimization ---------------------------------------------------
if [[ $CMIN == 1 && $INTERRUPTED == 0 ]]; then
  for T in $TARGETS; do
    echo "== cmin $T"
    cargo +nightly fuzz cmin "$T" "fuzz/corpus/$T" \
      >"$WORK/fuzz/logs/$STAMP-$LABEL-$T.cmin.log" 2>&1 || echo "!! cmin failed for $T (see log)"
    AFTER[$T]=$(ls "$WORK/fuzz/corpus/$T" 2>/dev/null | wc -l)
  done
fi

# ---- Sync results back into the repo ------------------------------------------------
mkdir -p "$REPO/fuzz/artifacts" "$REPO/fuzz/logs"
# Corpus mirroring is deliberately narrow (fuzz/README.md):
#   * only fuzz_load_mkpx's corpus goes back to the repo — the others are thousands of
#     tiny files that churn wholesale on every cmin and regenerate locally in minutes;
#   * only entries <= CORPUS_COMMIT_MAX, because fuzzing the boundary seeds breeds
#     multi-hundred-KB descendants (one 10-minute run produced 45 MB of them).
# Everything else stays in the WSL work tree, which is the real corpus of record.
CORPUS_COMMIT_MAX=65536
if [[ -d "$WORK/fuzz/corpus/fuzz_load_mkpx" ]]; then
  mkdir -p "$REPO/fuzz/corpus/fuzz_load_mkpx"
  if [[ $CMIN == 1 && $INTERRUPTED == 0 ]]; then
    rsync -a --delete --max-size=$CORPUS_COMMIT_MAX \
      "$WORK/fuzz/corpus/fuzz_load_mkpx/" "$REPO/fuzz/corpus/fuzz_load_mkpx/"
  else
    rsync -a --max-size=$CORPUS_COMMIT_MAX \
      "$WORK/fuzz/corpus/fuzz_load_mkpx/" "$REPO/fuzz/corpus/fuzz_load_mkpx/"
  fi
fi
rsync -a "$WORK/fuzz/artifacts/" "$REPO/fuzz/artifacts/"
rsync -a "$WORK/fuzz/logs/" "$REPO/fuzz/logs/"

# ---- Summary ------------------------------------------------------------------------
SUMMARY="$REPO/fuzz/logs/summary-$STAMP-$LABEL.md"
{
  echo "# Fuzz run $STAMP ($LABEL)"
  echo
  echo "Workers: $WORKERS · budget: $MINUTES min ($SECS_PER s/target) · cmin: $CMIN · interrupted: $INTERRUPTED"
  echo
  for T in $TARGETS; do
    EXECS=$(grep -h 'stat::number_of_executed_units' "$REPO/fuzz/logs/$STAMP-$LABEL-$T".fuzz-*.log 2>/dev/null \
      | awk '{s+=$NF} END{printf "%d", s}')
    COV=$(grep -ho 'cov: [0-9]*' "$REPO/fuzz/logs/$STAMP-$LABEL-$T".fuzz-*.log 2>/dev/null \
      | awk '{if ($2+0 > m) m=$2} END{printf "%d", m}')
    NCRASH=$(wc -w <<<"${CRASH_NEW[$T]}" | tr -d ' ')
    echo "## $T"
    echo
    echo "- executions: ${EXECS:-?} · peak cov: ${COV:-?} edges"
    echo "- corpus: ${BEFORE[$T]} -> ${AFTER[$T]} entries"
    if [[ "$NCRASH" != 0 ]]; then
      echo "- **NEW CRASH ARTIFACTS: $NCRASH** (fuzz/artifacts/$T/)"
      for C in ${CRASH_NEW[$T]}; do echo "  - \`$C\`"; done
    else
      echo "- new crash artifacts: none"
    fi
    echo
  done
  echo "Next steps for a crash: reproduce with \`cargo +nightly fuzz run <target> fuzz/artifacts/<target>/<file>\`,"
  echo "minimize with \`cargo +nightly fuzz tmin <target> <file>\`, then commit the reproducer as a new entry"
  echo "in \`crates/engine/tests/fuzz_inputs.rs\` (see fuzz/README.md)."
} >"$SUMMARY"

echo
echo "==================== SUMMARY ===================="
cat "$SUMMARY"
echo "== summary saved: $SUMMARY"
