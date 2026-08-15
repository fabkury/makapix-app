# Reproducing the measurements in `../ANALYSIS.md`

Five `mkpx` DSL scripts, each a single uninterrupted stroke painted with a **50 % alpha** red
(`#FF000080`). Run them against the `mkpx` harness and read the probed pixels; the table in
`../ANALYSIS.md` is these outputs verbatim (measured at commit `f748367`).

```sh
cargo build -p makapix-cli --release
M=./target/release/mkpx
D=docs/non-accumulating-brush/scripts

$M run $D/tap.txt     "pixel:0:0:16:16"                                   # 0x80 — the baseline
$M run $D/buildup.txt "pixel:0:0:16:16" "pixel:0:0:8:16" "pixel:0:0:24:16" # 0xE0 mid, 0xC0 ends
$M run $D/dense.txt   "pixel:0:0:16:16" "pixel:0:0:6:16"                  # same, 1 px pointer steps
$M run $D/scrub.txt   "pixel:0:0:16:16" "pixel:0:0:16:13"                 # 0xFF / 0xFC — saturated
$M run $D/line.txt    "pixel:0:0:16:16" "pixel:0:0:16:17" "pixel:0:0:16:18" # 0xF0 — Line, width 4
```

| Script | Gesture |
|---|---|
| `tap.txt` | one `PointerDown`/`PointerUp` at the same pixel |
| `buildup.txt` | straight drag, pointer events every 4 px (a fast flick) |
| `dense.txt` | straight drag, pointer events every 1 px (a slow drag) |
| `scrub.txt` | three passes back and forth over the same span, finger never lifted |
| `line.txt` | the Line tool at `SetLineWidth(4)` — single-shot over-plot, not a stroke |

`buildup.txt`, `dense.txt` and `scrub.txt` all use the shipped defaults the shell sends
(`SetBrushSize(8)`, `SetBrushShape(Round)`, `SetSpacing(25)`); changing `spacing` changes the
numbers but not the conclusion — no stroke longer than a tap lands on the requested alpha.
