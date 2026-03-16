# Changelog

All notable changes to the Agent Builder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
- **Framework guide** (`references/frameworks.md`) -- 11 framework reviews with selection matrix (22 use cases), head-to-head comparisons, and 2025 trend analysis.
- **Production hardening** (`references/production.md`) -- context engineering, tool design principles, evaluation strategy, cost modeling, observability, guardrails, failure modes, and deployment checklist.
- **5 code templates** -- simple agent, ReAct with persistence, multi-agent supervisor, parallel fan-out/fan-in, human-in-the-loop with interrupt.
- **Build system** -- Makefile (Unix/Linux/macOS) and build.ps1 (Windows PowerShell) for packaging and validation.
