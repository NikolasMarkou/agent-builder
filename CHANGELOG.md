# Changelog

All notable changes to the Agent Builder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
- **5 code templates** -- simple agent, ReAct with persistence, multi-agent supervisor, parallel fan-out/fan-in, human-in-the-loop with interrupt.
- **Build system** -- Makefile (Unix/Linux/macOS) and build.ps1 (Windows PowerShell) for packaging and validation.
