//! Drift guard for the actions fuzz target (fuzzing-review W2).
//!
//! `fuzz/fuzz_targets/fuzz_session_actions.rs` renders DSL lines for the parser in
//! `src/session/parse.rs`. Both sides change independently, and a gap fails silently: a new
//! verb the target never emits is never fuzzed, and a renamed verb the target still emits is
//! rejected by the parser and dropped from every sequence. This test reads both sources as
//! text and fails on either kind of drift. Every parser verb must be rendered by the target or
//! named on an `excluded verb: <Name> — <reason>` line in it; every tool `parse_tool` accepts
//! must appear in the target's `Tool::name`.

const PARSER: &str = include_str!("../src/session/parse.rs");
const TARGET: &str = include_str!("../../../fuzz/fuzz_targets/fuzz_session_actions.rs");

/// The body of `fn <name>` up to the next top-level `fn`.
fn fn_body<'a>(src: &'a str, name: &str) -> &'a str {
    let start = src.find(&format!("fn {}(", name)).unwrap_or_else(|| panic!("no fn {} in parse.rs", name));
    let rest = &src[start + 1..];
    let end = rest.find("\nfn ").or_else(|| rest.find("\npub fn ")).unwrap_or(rest.len());
    &rest[..end]
}

/// Every string literal that starts an outermost match arm (`"A" =>`, `"A" | "B" =>`) or is
/// compared with `name == "A"`. Arms of the nested argument matches (`"Loop" =>`) sit deeper,
/// so only the shallowest arm indentation counts.
fn arm_names(body: &str) -> Vec<String> {
    let mut out = Vec::new();
    let indent = |l: &str| l.len() - l.trim_start().len();
    let is_arm = |l: &str| l.trim_start().starts_with('"') && l.contains("=>");
    let top = body.lines().filter(|l| is_arm(l)).map(indent).min().unwrap_or(0);
    for line in body.lines() {
        let t = line.trim();
        if let Some(eq) = t.find("name == \"") {
            let rest = &t[eq + 9..];
            if let Some(q) = rest.find('"') {
                out.push(rest[..q].to_string());
            }
        }
        if !is_arm(line) || indent(line) != top {
            continue;
        }
        let head = t[..t.find("=>").unwrap()].trim();
        for alt in head.split('|') {
            let alt = alt.trim();
            if alt.len() >= 2 && alt.starts_with('"') && alt.ends_with('"') {
                out.push(alt[1..alt.len() - 1].to_string());
            }
        }
    }
    out.retain(|n| n.chars().next().is_some_and(|c| c.is_ascii_uppercase()));
    out.sort();
    out.dedup();
    out
}

/// Does the target emit `name(` as a DSL line? An emission starts a string literal (`"Name(`),
/// follows a `\n` escape inside one, or follows `; `.
fn rendered(name: &str) -> bool {
    let pat = format!("{}(", name);
    TARGET.match_indices(&pat).any(|(i, _)| {
        let before = &TARGET[..i];
        before.ends_with('"') || before.ends_with("\n") || before.ends_with("; ")
    })
}

fn excluded(name: &str) -> bool {
    TARGET.contains(&format!("excluded verb: {} ", name))
}

/// Every DSL verb the target emits: identifiers that start an emission (see `rendered`).
fn emitted() -> Vec<String> {
    let mut out = Vec::new();
    let b = TARGET.as_bytes();
    for i in 0..b.len() {
        let starts = (i >= 1 && b[i - 1] == b'"') || (i >= 2 && &b[i - 2..i] == b"\n");
        if !starts || !b[i].is_ascii_uppercase() {
            continue;
        }
        let end = (i..b.len()).find(|&j| !b[j].is_ascii_alphanumeric()).unwrap_or(b.len());
        if end < b.len() && b[end] == b'(' {
            out.push(TARGET[i..end].to_string());
        }
    }
    out.sort();
    out.dedup();
    out
}

#[test]
fn every_parser_verb_is_fuzzed_or_excluded() {
    let verbs = arm_names(fn_body(PARSER, "parse_line"));
    assert!(verbs.len() > 150, "verb extraction broke: only {} verbs found", verbs.len());
    let missing: Vec<&String> = verbs.iter().filter(|v| !rendered(v) && !excluded(v)).collect();
    assert!(
        missing.is_empty(),
        "parser verbs the actions fuzz target neither renders nor excludes: {:?}\n\
         add them to fuzz/fuzz_targets/fuzz_session_actions.rs, or add an \
         `excluded verb: <Name> — <reason>` line there",
        missing
    );
    for v in &verbs {
        assert!(!(rendered(v) && excluded(v)), "{} is both rendered and excluded", v);
    }
}

#[test]
fn every_emitted_verb_and_exclusion_names_a_parser_verb() {
    let verbs = arm_names(fn_body(PARSER, "parse_line"));
    let stale: Vec<String> = emitted().into_iter().filter(|e| !verbs.contains(e)).collect();
    assert!(stale.is_empty(), "the fuzz target emits verbs the parser rejects: {:?}", stale);
    for line in TARGET.lines() {
        if let Some(at) = line.find("excluded verb: ") {
            let name = line[at + 15..].split_whitespace().next().unwrap_or("");
            assert!(verbs.iter().any(|v| v == name), "stale exclusion: {} is not a parser verb", name);
        }
    }
}

#[test]
fn every_tool_is_fuzzed() {
    let tools = arm_names(fn_body(PARSER, "parse_tool"));
    assert!(tools.len() > 20, "tool extraction broke: only {} tools found", tools.len());
    let missing: Vec<&String> =
        tools.iter().filter(|t| !TARGET.contains(&format!("=> \"{}\"", t))).collect();
    assert!(missing.is_empty(), "tools missing from the fuzz target's Tool::name: {:?}", missing);
}
