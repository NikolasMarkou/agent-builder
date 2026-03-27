# Changelog

All notable changes to the Agent Builder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.10.0] - 2026-03-27

### Added
- **Working memory architecture guidance** in `production.md` -- agent memory taxonomy (forms × functions × scope), explicit working memory buffer structure, Agentic Context Engineering (ACE) pattern for incremental memory accumulation, and 3 new memory failure modes (context collapse, brevity bias, memory poisoning) with mitigations.
- **Multi-agent memory coordination patterns** in `patterns.md` -- shared, isolated, and hierarchical working memory patterns with when-to-use guidance, risks, and LangGraph implementation notes.
- **Mem0 and A-MEM** added to framework footnotes in `frameworks.md` -- expands the external-documentation-only memory framework references alongside Letta.

## [1.9.0] - 2026-03-26

### Added
- **DSPy dedicated reference** (`references/dspy.md`) -- comprehensive implementation reference covering Signatures, Modules, optimizer selection (with decision tree), RAG patterns (basic, multi-hop, agentic), multi-agent composition, integration patterns with LangGraph and Strands, evaluation, observability, deployment, and pattern mapping to the agent-builder catalogue. Positioned as an optimization layer that complements orchestration frameworks.
- **DSPy cross-references** -- SKILL.md Step 3 now points to `references/dspy.md` + `references/frameworks.md`; frameworks.md DSPy section links to the deep-dive reference.

## [1.8.0] - 2026-03-23

### Added
- **Scenario scaffolding reference** (`references/scaffolding.md`) -- pre-composed pattern recipes for 7 common agent scenarios: deep research, customer support/triage, code generation & review, data analysis & reporting, document processing pipelines, RAG/knowledge retrieval, and autonomous task execution. Each scenario includes topology diagrams, Python state shapes with proper reducers, production guardrails, and failure modes.
- **Composition escalation rule** in `patterns.md` -- 7-step escalation ladder (ReAct -> Sequential -> Loop -> Router -> Parallel -> Hierarchical -> Swarm/Network) for incrementally upgrading topology only when measured failures demand it.
- **Scenario matching** in Step 1 requirements checklist -- new checklist item to identify known scenarios and load `scaffolding.md`.
- **Scaffolding cross-references** in SKILL.md Steps 2 and 4 -- directs users to scenario-specific recipes after pattern selection and during build.

## [1.7.2] - 2026-03-20

### Fixed
- **DSPy missing from cross-validation gate table in SKILL.md** -- added DSPy column to the pattern support matrix and included DSPy in the non-orchestration framework caveat alongside LlamaIndex, Agno, and Smolagents.
- **Stale model strings across 7 reference files** -- updated all 22 occurrences of `claude-sonnet-4-5-20250929` to `claude-sonnet-4-6-20250514` in langchain-langgraph.md, patterns.md, deployment.md, frameworks.md, production.md, evals.md, and structured-classification.md.
- **Fragile Makefile reference extraction** -- replaced `ls | xargs -I{} basename {}` with `$(notdir $(REFERENCE_FILES))` using the existing Make variable; eliminates silent failure on empty directories.
- **Missing frontmatter closing delimiter validation** -- both Makefile and build.ps1 now validate the closing `---` in SKILL.md frontmatter, not just the opening.
- **Missing tar availability check in build.ps1** -- `package-tar` now checks for `tar` before attempting to create the tarball, with a clear error message suggesting the zip alternative.

## [1.7.1] - 2026-03-20

### Fixed
- **Multi-agent node functions in langchain-langgraph.md** -- nodes now pass dict input to `create_agent().invoke()` and return messages correctly instead of wrapping result in a list (would crash `add_messages` reducer).
- **Generator-Critic pattern in patterns.md** -- `gen_node` and `critic_node` now extract `.content` from agent invoke results instead of treating dicts as strings.
- **STORM `identify_gaps` in patterns.md** -- uses `with_structured_output(QueryList)` to return a proper list instead of assigning an `AIMessage` to the `queries` field (would crash on fan-out iteration).
- **Plan-and-Execute undefined `agent` in patterns.md** -- added `executor_agent` definition and corrected invoke call.
- **Aggregator fan-out in patterns.md** -- added missing path map `["analyst"]` to `add_conditional_edges` with `Send()`.
- **Undocumented `max_iterations` param in patterns.md** -- removed from `create_agent` call (not in API reference).
- **Health check private attribute in deployment.md** -- replaced `checkpointer._pool.connection()` with `checkpointer.conn.cursor()`.
- **Missing `import os` in deployment.md** -- added to memory implementation code block.
- **RateLimiter unbounded memory in production.md** -- added stale key eviction to prevent memory growth under sustained traffic.
- **Unreachable dead code in production.md** -- removed unreachable `raise RuntimeError("All models failed")` in `ModelRegistry`.
- **Google ADK API in frameworks.md** -- changed `.run()` to `.run_async()` to match current ADK API.
- **Import path inconsistency** -- standardized `entity-resolution.md` and `retrieval.md` to `from langchain.tools import tool` (matching `langchain-langgraph.md` convention).
- **MCP credential placeholder in langchain-langgraph.md** -- replaced hardcoded `"Bearer ..."` with `os.environ['GITHUB_MCP_TOKEN']`.
- **Makefile validation silently swallowing errors** -- all 5 `for` loops used `exit 1` inside subshells `()` which only exited the subshell; replaced with `{ }` braces and a `fail` flag so errors are never ignored.
- **README.md version badge** -- was stuck at v1.6.1, now tracks VERSION file correctly.

## [1.7.0] - 2026-03-20

### Added
- **New reference: `embeddings.md`** -- embedding model selection and evaluation guide. Covers three-pillar evaluation framework (intrinsic, extrinsic, robustness), task-specific evaluation protocols (retrieval/RAG, classification, clustering, STS, reranking), 7-step model selection decision framework, intrinsic evaluation methods with code (cosine distribution, neighborhood consistency, isotropy), production readiness testing (throughput, quantization degradation), MRL dimension reduction and quantization pipeline tables, domain-specific model recommendations (biomedical, legal, financial, code, multilingual), benchmarks reference, model-by-task matrix, and full evaluation checklist.
- **Cross-references to `embeddings.md`** added in `retrieval.md` (Dense Retrieval section + See Also footer), `SKILL.md` (Step 4 RAG reference loading), `README.md` and `CLAUDE.md` (repository structure).

## [1.6.1] - 2026-03-20

### Fixed
- **Missing imports in deployment.md** -- added `import os` and `from fastapi.responses import JSONResponse` to FastAPI skeleton and health check endpoint. Code examples now run as-is.
- **Hardcoded database password in deployment.md** -- docker-compose `POSTGRES_PASSWORD: agent` replaced with `${POSTGRES_PASSWORD}` environment variable, consistent with security guidance.
- **Deprecated import path in entity-resolution.md** -- `from langchain.tools import tool` corrected to `from langchain_core.tools import tool` (LangChain 1.2.x canonical path).
- **Incorrect sed flag in text-tools.md** -- removed false claim that sed has a `-F` flag (that's grep/ripgrep).
- **Duplicate conflicting GPT-4o cost row in entity-resolution.md** -- consolidated two contradictory rows into one.
- **Stale model string in structured-classification.md** -- `gpt-4o-2024-08-06` updated to `gpt-4o`.
- **Stale date in prompt-structuring.md** -- "as of 2025" updated to "as of early 2026".
- **Speculative model name in binary-evals.md** -- "GPT-5-nano" corrected to "GPT-4o-mini".
- **Inconsistent model name in llm-as-judge.md** -- "Claude-Opus-4" normalized to "Claude Opus".
- **Stale GA timeline in frameworks.md** -- removed outdated "GA Q1 2026" from Microsoft Agent Framework entry.
- **Vague license in frameworks.md** -- Mastra license corrected from "MIT-like" to "Elastic License 2.0 (ELv2)".
- **Ambiguous model reference in langchain-langgraph.md** -- "with Sonnet" clarified to "with Claude Sonnet".
- **Three-way failure modes duplication** -- consolidated failure modes into `patterns.md` as single source of truth; `langchain-langgraph.md` and `production.md` now cross-reference instead of duplicating.
- **Metrics table duplication in deployment.md** -- replaced duplicated 6-row table with cross-reference to `production.md`.
- **Eval content duplication in evals.md** -- replaced duplicated biases/calibration/cost sections with cross-reference to `llm-as-judge.md`.
- **Eval content duplication in production.md** -- trimmed 40-line evaluation section to 5-line summary with cross-reference to `evals.md`.
- **Single-process rate limiter in production.md** -- added note that in-memory implementation requires Redis for multi-worker deployments.

## [1.6.0] - 2026-03-20

### Added
- **Code examples for behavioral patterns** -- `patterns.md` code coverage raised from 26% to 79%: added runnable examples for ReAct (2.1), Reflection (2.2), Plan-and-Execute (2.3), Generator-Critic (2.4), STORM (2.5), HITL (2.6), Aggregator (1.5), and Hierarchical (1.7).
- **Code examples for production.md** -- added structured logging (JSON formatter with contextvars), rate limiter, model registry with 3-model fallback chain, and context management (SummarizationMiddleware + truncation helper). File previously had zero code blocks.
- **Failure modes and cost guidelines for langchain-langgraph.md** -- 7 failure modes with mitigations, per-pattern cost profiles with budget rules.
- **Failure modes for deployment.md** -- 6 deployment-specific failure modes with mitigations.
- **Deep Agents expansion** -- task planning section with middleware config (MemoryMiddleware, HumanInTheLoopMiddleware), sandbox options, when-to-use/when-NOT-to-use guidance.
- **"No agent needed" workflow path** -- SKILL.md Step 1 now provides 3 concrete non-agent alternatives (rule-based, single LLM call, structured output) instead of dead-ending.
- **Workflow iteration guidance** -- SKILL.md now explains how to backtrack from Step 4/5 to Step 2/3 when patterns or frameworks don't fit.
- **Custom multi-agent StateGraph example** -- complete planner→researcher→writer example in `langchain-langgraph.md`.

### Fixed
- **LangGraph Core example complete** -- Template 2 (ReAct with persistence) now defines all functions (`agent_node`, `tool_node`, `route`) with proper imports. Previously was a skeleton with undefined references.
- **Remaining deprecated model strings** -- fixed 9 instances across 5 files: `prompt-structuring.md` (GPT-4.1→GPT-4.1+), `tabular-data.md` (GPT-4.1-nano→GPT-4o-mini, GPT-4.1+→GPT-4o), `entity-resolution.md` (GPT-4.1→GPT-4o ×2), `production.md` (GPT-4.1/GPT-4.1-mini→GPT-4o/GPT-4o-mini), `llm-as-judge.md` (Claude-v1→earlier Claude models).
- **Validation pipeline broadened** -- model string regex now catches prose references (not just code context). Content guideline compliance promoted from WARNING to ERROR.
- **Undefined `is_simple_query`** -- replaced with inline logic in `langchain-langgraph.md` middleware routing example.
- **entity-resolution.md** -- renamed "LLMs struggle with" to "When NOT to use LLMs for ER" for content guideline compliance.

## [1.5.2] - 2026-03-20

### Fixed
- **Model string consistency (complete)** -- fixed remaining 5 `gpt-4.1` and 1 `gpt-4.1-mini` instances in `langchain-langgraph.md` → `gpt-4o`/`gpt-4o-mini`. Fixed stale `claude-sonnet-4-20250514` in `structured-classification.md` → `claude-sonnet-4-5-20250929`.
- **deployment.md code examples** -- added FastAPI skeleton, SSE streaming endpoint, health check endpoint, Dockerfile, docker-compose.yml, Prometheus configuration, metrics exposition, and memory implementation. File was previously 100% prose with zero working code.
- **Validation pipeline extended** -- `Makefile` and `build.ps1` validate targets now check: deprecated model strings (`gpt-4.1`), code example presence per reference file, and content guideline compliance (failure modes / "When NOT to use" sections).
- **CHANGELOG v1.5.1 accuracy** -- corrected v1.5.1 entry to reflect that model string fix was partial, not complete.

## [1.5.1] - 2026-03-20

### Fixed
- **Version badge drift** -- README.md badge now matches VERSION file; added automated version badge check to both `Makefile` and `build.ps1` validate targets to prevent future drift.
- **Cross-validation gate coverage** -- extended pattern support table in SKILL.md from 6 to all 10 frameworks (added Semantic Kernel, LlamaIndex, Agno, Smolagents) with note clarifying non-orchestration frameworks.
- **Selection matrix footnotes** -- frameworks referenced in the selection matrix but not covered in this guide (Haystack, AutoGen, Vercel AI SDK, Letta/MemGPT) now marked with `*` and footnote with brief descriptions.
- **Model string consistency** -- partially standardized OpenAI model references in `frameworks.md`; `langchain-langgraph.md` instances were missed (fixed in v1.5.2).

## [1.5.0] - 2026-03-20

### Added
- **Text retrieval reference** (`references/retrieval.md`) -- comprehensive guide to production retrieval for agentic AI: sparse retrieval (BM25, SPLADE), dense retrieval (bi-encoders, embedding model selection), late interaction (ColBERT), cross-encoders, hybrid search (RRF, DBSF, convex combination), pre-retrieval query transformation (HyDE, query decomposition, expansion), post-retrieval corrective loops (CRAG, Self-RAG, Adaptive RAG), GraphRAG and multi-hop retrieval, agentic RAG architectures with LangGraph code, chunking strategies, production tooling (vector DBs, frameworks), retrieval evaluation metrics, decision framework, and failure modes.
- **SKILL.md** -- Step 1 requirements checklist now detects RAG/knowledge-base retrieval needs; Step 4 loads `references/retrieval.md` when flagged.
- Cross-references added in `text-tools.md` (positioning code search vs. RAG), `deployment.md` (vector store retrieval patterns), `README.md`, and `CLAUDE.md`.

## [1.4.1] - 2026-03-19

### Fixed
- **Template naming** -- corrected "multi-agent supervisor" to "multi-agent swarm (handoffs)" in README.md and CHANGELOG.md to match the actual `create_swarm` implementation.
- **Code template pointer** -- clarified in CLAUDE.md that code templates live in `references/langchain-langgraph.md`, not in SKILL.md itself.

## [1.4.0] - 2026-03-18

### Added
- **Deployment reference** (`references/deployment.md`) -- API serving patterns (FastAPI), streaming responses, health checks, middleware stack, environment configuration, containerization (Docker), monitoring stack, and long-term memory guidance.
- **Design axioms** -- 6 principles (tiered escalation, decompose, model costs first, minimize context, calibrate on real data, document failure modes) added to SKILL.md with cross-domain callouts in reference files.
- **Decision State Blocks (DSBs)** -- structured state tracking emitted after each workflow step, preventing context loss between steps and ensuring later steps respect earlier decisions.
- **Requirements checklist** -- Step 1 now includes explicit checklist for identifying data requirements and which references to load.
- **Pattern-framework cross-validation gate** -- Step 3 now verifies selected framework supports patterns chosen in Step 2 before proceeding.
- **Tier routing** -- Simple agents skip Steps 2-3, going directly to Step 4 with `create_agent`.

### Changed
- **SKILL.md** -- trimmed from 355 to 182 lines by removing duplicated content and moving implementation details to reference files. Added FSM-style workflow interventions for structural reliability.
- **production.md** -- extended with security hardening (input sanitization, rate limiting, authentication), LLM service resilience (model registry with fallback, retry with backoff, connection pooling, graceful degradation), and enhanced observability (structured logging, metrics definitions, tracing platform comparison).
- **evals.md** -- extended with core eval dimensions for agents (hallucination, toxicity, helpfulness, relevancy, conciseness), rubric design patterns, dimension selection by agent type, and operational guidance for running evaluations at scale.
- **README.md** -- updated to reflect design axioms, DSBs, cross-validation gate, and deployment reference.
- Cross-references and documentation inconsistencies fixed across the repository.

## [1.3.0] - 2026-03-16

### Added
- **Text tools reference** (`references/text-tools.md`) -- cheap deterministic text tools for AI agents: three-layer search stack (exact/structural/semantic), tool-by-tool reference (ripgrep, ast-grep, jq, yq, sed, awk, sqlite3), agent-optimized search tools (Probe, grepika, grepai, mgrep, AI-grep, llm_grep), sandboxed execution (just-bash), cost math (10-50x savings), tool selection decision tree, integration patterns (MCP servers, system prompts, bash tool wrappers), and anti-patterns.

### Changed
- **SKILL.md** -- Step 4 (Build) now references `text-tools.md` for agents using text search, data filtering, or code navigation tools. Reference table updated with text-tools.md entry.
- **README.md** -- Updated project structure to list text-tools.md.
- **CLAUDE.md** -- Updated repository structure to list text-tools.md.

## [1.2.0] - 2026-03-16

### Added
- **Prompt structuring reference** (`references/prompt-structuring.md`) -- delimiter format selection (XML/Markdown/YAML), 7-block prompt architecture, prompting techniques (zero-shot, few-shot, CoT, chaining, meta, self-consistency), output control, position bias, model-specific notes, and anti-patterns.
- **Tabular data reference** (`references/tabular-data.md`) -- serialization format benchmarks (ImprovingAgents, TOON), size-based strategies (<50 / 50-500 / 500+ rows), format selection decision tree, token cost comparison, and model-specific notes.
- **LLM-as-Judge reference** (`references/llm-as-judge.md`) -- implementation patterns (pointwise/pairwise/reference-guided), 12 documented biases and mitigations, calibration process, rubric design (binary > Likert), judge model selection (PoLL panels), statistical rigor, agent trajectory evaluation, production deployment pipelines, and 6 evaluation frameworks.
- **Binary evaluation rules reference** (`references/binary-evals.md`) -- the case for binary decomposition over Likert scales, CheckEval framework, Google's Adaptive Precise Boolean approach, 4 implementation patterns, scale selection decision tree, prompt templates, composite scoring, and calibration with classification metrics.

### Changed
- **SKILL.md** -- Step 4 (Build) now references `prompt-structuring.md` for system prompt design and `tabular-data.md` for agents processing tabular data. Reference table updated with all new entries.
- **patterns.md** -- Added "When NOT to use" sections and code examples to all patterns.
- **frameworks.md** -- Added "When NOT to choose" sections to all frameworks.
- **Makefile** -- Extended `validate` target to check README and CLAUDE.md project structure sections against actual reference files.
- **build.ps1** -- Extended `validate` function with same documentation drift checks.
- **README.md** -- Updated project structure to list all reference files.

## [1.1.0] - 2026-03-16

### Added
- **Evaluation reference** (`references/evals.md`) -- comprehensive evaluation guide covering frameworks (Anthropic three-grader, capability vs regression evals, Google Cloud three pillars), benchmarks (SWE-bench, WebArena, GAIA, τ-bench, Cybench, etc.), metrics (outcome, process, cost, safety), LLM-as-judge (paradigms, biases, calibration), human evaluation, safety evaluation (OWASP Top 10, red-teaming tools), production monitoring (platform comparison, OpenTelemetry), eval pipeline architecture (promptfoo, Inspect AI, DeepEval), and best practices with 10 anti-patterns.

### Changed
- **SKILL.md** -- Step 5 now references `evals.md` for comprehensive evaluation guidance; reference table updated with evals.md entry.
- **production.md** -- Evaluation Strategy section now cross-references `evals.md` for in-depth coverage.

## [1.0.0] - 2026-03-16

### Added
- **Initial release** -- 5-step workflow for building production-grade AI agents from requirements.
- **SKILL.md** -- core skill definition with assessment, pattern selection, framework selection, build, and production hardening workflow.
- **Pattern catalogue** (`references/patterns.md`) -- 19 patterns across three layers: topology (7), behavioral (7), data flow (5). Includes composition rules and failure mode catalogue.
- **Default stack reference** (`references/langchain-langgraph.md`) -- LangChain v1.2.x + LangGraph v1.0.x implementation reference covering state management, edges, persistence, streaming, memory, middleware, MCP integration, multi-agent patterns, and Deep Agents.
- **Framework guide** (`references/frameworks.md`) -- 10 alternative framework reviews with selection matrix (18 use cases), head-to-head comparisons, and 2025-2026 trend analysis.
- **Production hardening** (`references/production.md`) -- context engineering, tool design principles, evaluation strategy, cost modeling, observability, guardrails, failure modes, and deployment checklist.
- **5 code templates** -- simple agent, ReAct with persistence, multi-agent swarm (handoffs), parallel fan-out/fan-in, human-in-the-loop with interrupt.
- **Build system** -- Makefile (Unix/Linux/macOS) and build.ps1 (Windows PowerShell) for packaging and validation.
