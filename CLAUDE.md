# CLAUDE.md

Guidance for working with the Agent Builder codebase.

## Project Purpose

Claude Code skill -- builds, reviews, troubleshoots, and optimizes production-grade AI agents. Build workflow (5-step): Assess requirements > Select patterns > Select framework > Build > Production harden. Operational workflows: Review (architecture audit), Troubleshoot (symptom-based diagnostic), Optimize (cost/performance/prompt).

Use cases: building agents from scratch, selecting patterns/frameworks, designing multi-agent architectures, production-hardening existing agents, reviewing existing agent architectures, troubleshooting agent issues, optimizing agent cost/performance/prompts, extending agents with new capabilities.

## Repository Structure

```
agent-builder/
├── README.md                         # User documentation
├── LICENSE                           # GNU GPLv3
├── VERSION                           # Single source of truth for version number
├── CHANGELOG.md                      # Version history
├── CLAUDE.md                         # This file
├── Makefile                          # Unix/Linux/macOS build script (reads VERSION)
├── build.ps1                         # Windows PowerShell build script (reads VERSION)
└── src/
    ├── SKILL.md                      # Core skill (build workflow, review/troubleshoot/optimize workflows) - the main instruction set
    └── references/                   # Knowledge base documents (loaded on-demand)
        ├── patterns.md               # Pattern catalogue: topology (7), behavioral (7), data flow (5)
        ├── langchain-langgraph.md    # Default stack: LangChain v1.2.x + LangGraph v1.0.x
        ├── frameworks.md             # 10 framework reviews, selection matrix, head-to-head comparisons
        ├── strands.md                # Strands Agents: patterns, multi-agent, deployment, A2A protocol
        ├── dspy.md                   # DSPy: signatures, modules, optimizers, orchestration integration
        ├── production.md             # Context engineering, tool design, evals, cost, observability, guardrails, security, resilience
        ├── deployment.md             # Deployment: API serving (FastAPI), Docker, monitoring stack, long-term memory
        ├── evals.md                  # Evaluation: frameworks, benchmarks, metrics, LLM-as-judge, safety, monitoring
        ├── prompt-structuring.md     # Prompt structure: delimiters, 7-block template, techniques, output control
        ├── tabular-data.md           # Tabular data serialization: formats, size strategies, token costs
        ├── llm-as-judge.md           # LLM-as-Judge: patterns, biases, calibration, rubrics, production deployment
        ├── binary-evals.md           # Binary evaluation rules: CheckEval, boolean rubrics, scale selection
        ├── entity-resolution.md      # Entity resolution: blocking, matching, clustering, multi-agent ER
        ├── text-tools.md             # Text tools: search stack, ripgrep, ast-grep, jq, sqlite3, cost math
        ├── retrieval.md              # Text retrieval: sparse/dense/hybrid search, reranking, RAG, GraphRAG
        ├── embeddings.md             # Embedding model selection, evaluation protocols, efficiency trade-offs
        ├── structured-classification.md # Structured classification: intent detection, routing, constrained decoding
        └── scaffolding.md            # Scenario scaffolding: recipes for research, support, code gen, RAG, and more
```

## Activation Triggers

Agent-building requests, or: "build me an agent", "create an agent", "design agent architecture", "what framework should I use", "make this production-ready", "scaffold an agent project".

Also triggers on operational requests: "review my agent", "audit my agent architecture", "why is my agent slow/expensive", "fix my agent", "my agent hallucinates", "optimize my agent", "reduce agent cost", "improve my prompts", "add memory/HITL/streaming to my agent", "migrate from X to Y framework".

## Skill Reference

Complete spec in **src/SKILL.md**. Key sections:

- **Query Router**: src/SKILL.md "Query Router" section (classifies: Build, Review, Troubleshoot, Optimize, Extend)
- **Build Workflow (5-Step)**: src/SKILL.md "Build Workflow" section (assess, patterns, framework, build, harden)
- **Review Workflow**: src/SKILL.md "Review Workflow" section (map architecture, check pattern fit, production readiness audit)
- **Troubleshoot Workflow**: src/SKILL.md "Troubleshoot Workflow" section (symptom table, diagnose, fix)
- **Optimize Workflow**: src/SKILL.md "Optimize Workflow" section (cost, performance, prompt optimization)
- **Complexity Classes**: src/SKILL.md Step 1 table (Simple → Batteries-included)
- **Pattern Selection**: src/SKILL.md Step 2 + `src/references/patterns.md` (19 patterns across 3 layers)
- **Framework Selection**: src/SKILL.md Step 3 table + `src/references/frameworks.md` (10 frameworks, 18 use cases)
- **Code Templates**: src/SKILL.md "Code Templates" section → `src/references/langchain-langgraph.md` (5 templates)
- **Production Hardening**: src/SKILL.md Step 5 + `src/references/production.md`
- **Evaluation**: src/SKILL.md Step 5 + `src/references/evals.md` (frameworks, benchmarks, metrics, tooling, anti-patterns)
- **Default Stack**: `src/references/langchain-langgraph.md` (state, edges, streaming, memory, middleware, MCP, Deep Agents)

Do not duplicate skill content here. Read src/SKILL.md directly.

## Working with This Codebase

### File Modification Guidelines

- **src/SKILL.md** -- core skill. Changes affect all agent-building behavior. Keep focused on workflow; detailed implementation goes in reference files.
- **src/references/** -- supplementary knowledge, read on-demand. Add new files for expanded guidance. Don't duplicate content across files.
- **VERSION** -- single source of truth. `Makefile` + `build.ps1` read from it. Bump only `VERSION` + `CHANGELOG.md`.
- Code examples must use current API versions (LangChain 1.2.x, LangGraph 1.0.x as of March 2026).
- When adding a new framework, add it to both `src/references/frameworks.md` and the selection table in `src/SKILL.md`.

### Content Guidelines

- All reference material must be actionable -- code examples, decision tables, concrete patterns. No vague guidance.
- Use tables for decision matrices and comparisons.
- Use "When to use / When NOT to use" sections for every pattern and framework.
- Include failure modes and mitigations, not just happy paths.
- Keep code templates minimal but functional -- enough to copy-paste and adapt.

### Build Commands

```bash
# Windows (PowerShell)
.\build.ps1 build            # Build skill package structure
.\build.ps1 build-combined   # Build single-file skill with inlined references
.\build.ps1 package          # Create zip package
.\build.ps1 package-combined # Create single-file skill in dist/
.\build.ps1 package-tar      # Create tarball package
.\build.ps1 validate         # Validate skill structure
.\build.ps1 clean            # Remove build artifacts
.\build.ps1 list             # Show package contents
.\build.ps1 help             # Show available commands

# Unix/Linux/macOS
make build                   # Build skill package structure
make build-combined          # Build single-file skill with inlined references
make package                 # Create zip package (default)
make package-combined        # Create single-file skill package
make package-tar             # Create tarball package
make validate                # Validate skill structure
make clean                   # Remove build artifacts
make list                    # Show package contents
make help                    # Show available targets
```

### Validation Checklist

- [ ] `.\build.ps1 validate` passes (or `make validate`)
- [ ] src/SKILL.md has `name:` and `description:` in YAML frontmatter
- [ ] All cross-references in src/SKILL.md point to existing files in `src/references/`
- [ ] README.md project structure lists all files in `src/references/`
- [ ] CLAUDE.md repository structure lists all files in `src/references/`
- [ ] Framework selection table in SKILL.md matches frameworks covered in `src/references/frameworks.md`
- [ ] Code examples use current API versions (LangChain 1.2.x, LangGraph 1.0.x)

### Testing Changes

Validate skill changes by testing with prompts like:
- "Build me an agent that does X" (should route to Build Workflow, trigger the full 5-step workflow)
- "What framework should I use for Y?" (should consult framework selection matrix)
- "Make this production-ready" (should reference production.md guidance)
- "How should I evaluate my agent?" (should reference evals.md guidance)
- "Review my agent's architecture" (should route to Review Workflow, map patterns + audit readiness)
- "My agent is hallucinating" (should route to Troubleshoot Workflow, symptom table → diagnose → fix)
- "Reduce my agent's cost" (should route to Optimize Workflow, cost optimization steps)
- "Add memory to my agent" (should route to Extend, go to Step 4 + Step 5)

## Updating Local Skill

When asked to "update local skill", copy **everything** from the repo to `~/.claude/skills/agent-builder/` -- no exceptions, no partial copies:

```bash
# Full sync -- mirrors repo structure exactly
cp src/SKILL.md ~/.claude/skills/agent-builder/SKILL.md
cp -r src/references/ ~/.claude/skills/agent-builder/references/
cp README.md LICENSE CHANGELOG.md ~/.claude/skills/agent-builder/
```

Always verify with `diff -rq` after copying. Every file, every time.
