<!-- benchmarks-as-of: 2026-06 -->
# Direct Corpus Interaction (DCI)

Retrieval-augmented generation (RAG) preprocesses a corpus into an index, and the LLM only ever sees what the index chooses to return. The semantic understanding lives in the embedding model and the chunker — decisions frozen at index time. Direct Corpus Interaction (DCI) inverts this: it hands the LLM a terminal over the raw corpus. The agent decides what to search, runs the search itself, reads the result, then decides the next search. There is no offline index and no fixed retrieval boundary; the semantic understanding lives in the model at inference time, not in a precomputed vector space.

This matters most when precision is the bottleneck. On closed-corpus deep-research benchmarks, the DCI *localization* score — how tightly the agent narrows to the exact lines that answer the question — is more than 2x the best embedding retriever (Li et al., 2026, in published closed-corpus deep-research benchmarks). DCI wins not by retrieving *more* documents but by extracting more value from the documents it reaches: it can re-search, intersect constraints, and read surrounding context on demand, instead of being limited to the top-k chunks a one-shot retriever happened to surface.

> **Design axiom: the corpus is a filesystem, the agent is a developer at a terminal.** Every search is a shell command that can be composed, piped, and refined.

## Contents

1. [When to use DCI / When NOT](#when-to-use-dci--when-not)
2. [Tooling (cross-link, do not duplicate)](#tooling-cross-link-do-not-duplicate)
3. [Corpus preparation](#corpus-preparation)
4. [The six operation patterns](#the-six-operation-patterns)
5. [Agent prompt design](#agent-prompt-design)
6. [Context-window management](#context-window-management)
7. [Scaling DCI](#scaling-dci)
8. [Hybrid architectures](#hybrid-architectures)
9. [Decision guide: DCI vs semantic RAG vs hybrid](#decision-guide-dci-vs-semantic-rag-vs-hybrid)
10. [Production considerations](#production-considerations)
11. [DCI Across Environments](#dci-across-environments)
12. [Failure Modes](#failure-modes)

---

## When to use DCI / When NOT

Decide this first — DCI is powerful but lexical, and applying it to fuzzy queries wastes turns.

**WHEN to use DCI:**
- The corpus is a filesystem or otherwise grep-able (plain text, logs, source, tickets, transcripts).
- Queries hinge on **exact strings**: entities, error codes, IDs, function names, SKUs, citations.
- Multi-hop questions with **exact constraints** that intersect (date + person + place + count).
- The corpus **evolves daily** (logs, commits, tickets) — DCI needs no re-indexing, ever.
- The schema is **unknown or heterogeneous** — the agent discovers structure by exploring.
- You need **auditable, line-level evidence** (every claim cites a real file path and line).

**WHEN NOT to use DCI:**
- Fuzzy, conceptual, synonym-heavy queries ("documents *about* X") — lexical search misses paraphrases. Use semantic RAG instead (see `retrieval.md`).
- The corpus far exceeds your local search budget with no pre-filter — use a hybrid pre-filter (see [Hybrid architectures](#hybrid-architectures)) or semantic RAG.

Cross-link: this is the third branch of `retrieval.md` "When RAG vs. When Not" — that table stops at "fits in context? load directly," and DCI fills the "too large for context but grep-able" gap.

---

## Tooling (cross-link, do not duplicate)

`rg` (ripgrep) is the workhorse; `find`/`ls` for navigation; `head`/`sed`/`tail` for bounded reads; `wc` for counting; chained `rg ... | rg ...` for AND-conjunction. For the full flag reference, cost math, sandboxing (just-bash), and the bash-tool-wrapper pattern, see `text-tools.md` — DCI *composes* those primitives, it does not redefine them.

Empirical tool mix from trajectory analysis (Li et al., 2026): Bash ~62%, built-in file-search tools ~33%. Within bash, the dominant intents are `rg | head` (search + limit) and `rg | rg` (chained narrowing). Takeaway: a good DCI agent almost never `cat`s a whole document — it localizes, peeks at surrounding context, and moves on.

---

## Corpus preparation

DCI needs **no** offline indexing — there is no embedding pass, no vector store to provision, and nothing to re-build when documents change. But the corpus layout is now the agent's only map of the territory, so a few cheap conventions pay for themselves in fewer tool calls per question:

- Prefer **flat `.txt`, one document per file** — simple to grep, simple to read in bounded slices.
- Use **human-readable filenames** (title, not opaque hash) so the agent can discover candidates via `ls`/`find` before grepping content.
- Impose a **topic- or domain-based directory hierarchy** so whole subtrees can be eliminated before any content grep.
- **JSONL is acceptable** for structured metadata, but it is less friendly to `head`/`sed` line slicing.
- **Pre-convert PDF/DOCX/HTML to text** — `rg` cannot search binaries.
- **Strip boilerplate**, but keep section headers — they make excellent landmark patterns for in-document search.

```bash
corpus/
  finance/
    2025-q3-revenue-recognition.txt
    2025-q3-audit-findings.txt
  legal/
    msa-acme-2024.txt
ls corpus/finance/                 # discover before grepping
rg -l "ASC 606" corpus/finance/    # eliminate the legal/ subtree first
```

---

## The six operation patterns

Nearly every DCI trajectory is a sequence drawn from six recurring operations. They form a natural progression — orient, surface, narrow, read, probe, compare — and an agent that names which operation it is performing tends to spend fewer turns than one that improvises.

| # | Pattern | Trigger | Mechanism | Example |
|---|---|---|---|---|
| 1 | Corpus Exploration | orient before searching | scan dir structure | `ls corpus/; find corpus -maxdepth 2 \| head` |
| 2 | Broad Keyword Search | surface candidate files | corpus-level match | `rg -l "term" corpus/` |
| 3 | Iterative Narrowing | prune search space | chained constraints | `rg "A" corpus/ \| rg "B" \| head` |
| 4 | Targeted Document Reading | inspect a promising file | bounded read | `sed -n '50,150p' file.txt` |
| 5 | In-Document Deep Search | probe within one doc | multi-keyword | `rg -n "X\|Y" file.txt` |
| 6 | Cross-Document Comparison | verify / disambiguate | alternate across files | `rg -n "1966" fileA fileB fileC` |

> **Design axiom: narrow before you read.** The most effective trajectories spend proportionally more time on patterns 2-3; agents that jump to full reads (4/6) too early tend to fail.

---

## Agent prompt design

Principles:
- **Restrict to the corpus.** "Answer using ONLY documents in `@corpus`" suppresses hallucination and forces every claim to be grounded in a real file.
- **Instruct parallel searches.** Batch multiple `rg` calls per turn — one-tool-per-turn sequencing inflates turn count and cost 2-3x.
- **Require ruling out competitors.** Before committing to an answer, the agent must search for and dismiss competing candidates.
- **Require structured output.** Explanation with inline `[@corpus/path]` citations, then Exact Answer, then Confidence %.
- For IR/ranking variants, emphasize **recall AND precision** — NDCG penalizes both missing and spurious results.

```text
You are a corpus analyst. Answer using ONLY documents under @corpus.
Tools: rg, find, ls, head, sed, tail, wc (read-only).
Procedure:
  1. Explore structure, then run SEVERAL targeted rg searches in parallel.
  2. Narrow with chained constraints before reading any full file.
  3. Rule out competing candidates before committing.
Output:
  Explanation: <reasoning with inline [@corpus/relative/path] citations>
  Exact Answer: <span>
  Confidence: <0-100>%
```

---

## Context-window management

A DCI run is a stream of tool outputs, and that stream accumulates fast: a few dozen `rg` calls can bury the agent's own reasoning under raw search results. So a truncation and compaction policy is part of the design, not an afterthought — the right policy raises accuracy, the wrong one silently discards the evidence the agent needed. Measured accuracy on a 100-question closed-corpus subset (Li et al., 2026):

| Level | Per-call truncation | Compaction | Summarization | Accuracy | Note |
|---|---|---|---|---|---|
| L0 | none | no | no | 72% | baseline |
| L1 | 50K chars | no | no | 75% | fastest, max evidence retained |
| L2 | 20K chars | no | no | 69% | too aggressive — loses evidence |
| L3 | 20K chars | >240K accumulated, keep last 12 turns | no | 77% | **BEST** |
| L4 | 20K chars | same compaction | yes (post-compaction) | 73% | summarization flattens search structure |

Choosing a level:
- Short-horizon (<30 turns) → **L1**.
- Medium (30-100 turns) → **L3**.
- Very long (>100 turns) → **L4**, accepting the ~4% drop.
- Cost-first → **L2**.

Key insight: compaction keeps **which tools ran in what order** (the search trajectory) while discarding raw results. Never silently truncate — always append a truncation notice so the agent knows evidence was clipped and issues a targeted follow-up search.

---

## Scaling DCI

**Latency at scale.** A naive recursive grep over a 20GB dump is 10-30s per command, and accuracy degrades with corpus size: roughly ~100K docs → ~80% accuracy / 38 tool calls; ~200K → ~66% / 87 calls; ~400K → ~37% / 122 calls (GrepSeek, 2026). Beyond a few hundred thousand documents, raw recursive grep is no longer viable on its own.

**Sharded-parallel execution.** Split the corpus into N shards and run semantics-preserving pipelines across all shards concurrently, then merge by operation type: filter results concatenate, counts sum, sorted results merge-sort. This recovers most of the per-command latency lost at scale without changing the agent's mental model.

**Persistent search daemon.** Keep a long-lived search process with the corpus resident in RAM to amortize per-call subprocess spin-up. This matters when an agent issues dozens of `rg` calls per question and process startup dominates wall-clock time.

**Compact trained agents.** A small model can learn DCI via cold-start SFT on verified search trajectories, then GRPO refinement against a correctness-plus-format reward. Skipping the SFT stage produces degenerate behavior — `cat *` dumps and empty-pattern `rg ""` scans that flood the context — so the supervised warm-up is not optional.

---

## Hybrid architectures

When pure DCI hits the corpus-size wall, the answer is rarely "switch to RAG" — it is to compose a cheap pre-filter with DCI's precise localization, or to let DCI and a structured index check each other. Four variants recur in practice:

- **Semantic pre-filter + DCI localization.** A retriever (BM25 / dense / RRF) cuts the corpus to ~5-20K candidate docs, materialized as a flat directory; DCI then does precise localization and exact-constraint enforcement. This is the practical default for corpora above ~200K docs (see `retrieval.md` for the retriever stack).
- **DCI + GraphRAG.** Mine successful DCI trajectories to discover which entity pairs and transitions actually matter, build the knowledge graph from that evidence, serve it via GraphRAG, and keep DCI as a verification layer (see `multi-hop-rag.md`).
- **A-RAG hierarchical interface.** Expose keyword → sentence → chunk tools at increasing granularity. Same "reduce the search space before expensive operations" insight as DCI, delivered through tiered tools.
- **Interact-RAG.** Expose the retriever's internals (retrieve / inspect_scores / adjust_query / expand_context / filter) as agent-callable primitives — the complement to DCI when the corpus is too large for raw shell search.

---

## Decision guide: DCI vs semantic RAG vs hybrid

This is the highest-value table in the file: it answers "should I reach for DCI at all, and if so in what configuration?" Read it axis by axis — a corpus can point to DCI on one axis (exact-string queries) and to hybrid on another (sheer size), and the hybrid column is where those tensions resolve.

| Axis | Pure DCI | Semantic RAG | Hybrid |
|---|---|---|---|
| Corpus size | <50K docs comfortably; usable to ~100K with L3 context mgmt | any (index amortizes) | 50-200K (pre-filter pays off), >200K (mandatory, + sharding) |
| Query type | exact string / entity / error code / function name; multi-hop with exact constraints (or A-RAG) | fuzzy conceptual / synonym-heavy | mixed exact + conceptual |
| Corpus dynamics | evolving daily (no re-index); unknown / heterogeneous schema | static, governed, auditable index | evolving with a stable core |
| Cost / infra | no RAG infra — start here | vector DB already deployed | DB deployed → add DCI as a verification/localization layer; use DCI traces to find where chunking fails |

The <50K figure is a *preference* threshold, not a hard limit: pure DCI still answers at ~80% around 100K docs (see Scaling above) and degrades past ~200K — the table routes to hybrid where a pre-filter starts paying off, not where DCI stops working. Cross-link: this extends `retrieval.md` "When RAG vs. When Not" with a third (DCI) branch — for corpora too large to load but small or governed enough to grep.

---

## Production considerations

**Sandboxing.**
- Mount the corpus **read-only**, with **no network**.
- Restrict tools to read-only filesystem commands: `rg`, `grep`, `find`, `ls`, `head`, `tail`, `sed`, `cat`, `wc`, `sort`, `uniq`.
- Block mutating commands (`rm`, `mv`, `cp`, `curl`, `wget`) and `find --exec` / mutating `xargs`.
- **Validate every cited path** resolves to a real corpus file — reject hallucinated citations.
- Cross-link `text-tools.md` "just-bash" for the sandboxing mechanism.

**Cost.**
- Set a **hard turn budget** (e.g. 300) and prompt for parallel searches.
- L3 compaction yields ~15% turn reduction.
- Illustrative figures on an 830-question benchmark: a Claude-Code + `claude-sonnet-4-6` harness runs ~$1.2/question; a smaller `claude-haiku-4-5`-class harness runs ~$0.1/question.

**Observability.**
- Log full trajectories.
- Track **coverage** (did the gold document surface at all?) and **localization** (how tightly did the agent narrow?) — these separate "retrieval failed" from "reasoning failed."

---

## DCI Across Environments

The same six operation patterns hold whether the corpus lives on a **local filesystem**, an **object store** (e.g. S3 — flat keys, list+select+get, no recursive grep, per-call latency and request cost), or a **managed search index** (e.g. Azure AI Search — full-text plus OData filter plus by-id reads, all exposed as agent tools). Only the primitives change; the agent's localize-narrow-read loop is identical.

| DCI primitive | Local filesystem | Object store | Managed search index |
|---|---|---|---|
| Navigate structure | `ls` / `find` | list prefix (paginated) | enumerate index / facets |
| Find by name | `find -name` | list with key prefix | filter on a name field |
| Exact string search | `rg "term"` | get object, then local grep | full-text query |
| AND-conjunction | `rg A \| rg B` | fetch + local intersect | combined query filter |
| Count | `rg -c` / `wc -l` | list + tally | result count metadata |
| Read specific lines/chunk | `sed -n '50,150p'` | ranged byte get | by-id document read |
| Read surrounding context | `rg -C 5` | fetch neighbor byte range | fetch neighbor chunk by id |
| Navigate adjacency | next/prev line | next/prev key | next/prev chunk id |
| Domain/date filter | subtree path | key prefix convention | OData `$filter` |

> **Design axiom: make adjacency explicit.** On a local filesystem the agent can read any line at will; in chunked or remote stores, evidence often spans chunk boundaries, so neighbor-chunk navigation must be a first-class, low-friction operation in both your tools and your prompt.

---

## Failure Modes

| Failure mode | Symptom | Cause | Mitigation |
|---|---|---|---|
| Broad grep flood | `rg "the" corpus/` returns everything | prompt lacks specificity | require targeted keywords |
| Synonym miss | can't find "ASC 606" vs "revenue recognition" | no semantic expansion | add a synonym step or a hybrid pre-filter |
| Context exhaustion | hits turn limit without converging | corpus too large / early broad searches | L2+ truncation, domain pre-filter, reduce scope |
| Spurious citation | cites a path that does not exist | hallucination | validate every citation against the filesystem |
| Pipeline deadlock | chained conjunction returns nothing, agent loops variants | terms never co-occur | after 3 empty attempts, decompose into separate searches |
| Over-reading | `cat` on a 500K-char file | no inspection discipline | hard-cap reads, prefer `head`/`sed` |
| Compaction over-loss | L4 accuracy < L3 | summarization flattens intermediate search structure | default L3, escalate to L4 only past ~150 turns |

**See also:** `text-tools.md` (search-tool flag reference, cost math, just-bash sandboxing) · `retrieval.md` (semantic and hybrid retrieval, the when-RAG decision) · `multi-hop-rag.md` (iterative and graph-based multi-hop) · `scaffolding.md` (agent scenario recipes).
