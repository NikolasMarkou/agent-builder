# CLAUDE.md

Guidance for working with the Agent Builder codebase.

## Project Purpose

Claude Code skill -- builds production-grade AI agents from requirements. 5-step workflow: Assess requirements > Select patterns > Select framework > Build > Production harden.

Use cases: building agents from scratch, selecting patterns/frameworks, designing multi-agent architectures, production-hardening existing agents.

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
    ├── SKILL.md                      # Core skill (5-step workflow, code templates) - the main instruction set
    └── references/                   # Knowledge base documents (loaded on-demand)
        ├── patterns.md               # Pattern catalogue: topology (7), behavioral (7), data flow (5)
        ├── langchain-langgraph.md    # Default stack: LangChain v1.2.x + LangGraph v1.0.x
        ├── frameworks.md             # 11 framework reviews, selection matrix, head-to-head comparisons
        ├── production.md             # Context engineering, tool design, evals, cost, observability, guardrails
        ├── evals.md                  # Evaluation: frameworks, benchmarks, metrics, LLM-as-judge, safety, monitoring
        └── prompt-structuring.md     # Prompt structure: delimiters, 7-block template, techniques, output control
```

## Activation Triggers

Agent-building requests, or: "build me an agent", "create an agent", "design agent architecture", "what framework should I use", "make this production-ready", "scaffold an agent project".

## Skill Reference

Complete spec in **src/SKILL.md**. Key sections:

- **5-Step Workflow**: src/SKILL.md "Workflow" section (assess, patterns, framework, build, harden)
- **Complexity Classes**: src/SKILL.md Step 1 table (Simple → Batteries-included)
- **Pattern Selection**: src/SKILL.md Step 2 + `src/references/patterns.md` (19 patterns across 3 layers)
- **Framework Selection**: src/SKILL.md Step 3 table + `src/references/frameworks.md` (11 frameworks, 22 use cases)
- **Code Templates**: src/SKILL.md "Code Templates" section (5 templates)
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
- [ ] Framework selection table in SKILL.md matches frameworks covered in `src/references/frameworks.md`
- [ ] Code examples use current API versions (LangChain 1.2.x, LangGraph 1.0.x)

### Testing Changes

Validate skill changes by testing with prompts like:
- "Build me an agent that does X" (should trigger the full 5-step workflow)
- "What framework should I use for Y?" (should consult framework selection matrix)
- "Make this production-ready" (should reference production.md guidance)
- "How should I evaluate my agent?" (should reference evals.md guidance)

## Updating Local Skill

When asked to "update local skill", copy **everything** from the repo to `~/.claude/skills/agent-builder/` -- no exceptions, no partial copies:

```bash
# Full sync -- mirrors repo structure exactly
cp src/SKILL.md ~/.claude/skills/agent-builder/SKILL.md
cp -r src/references/ ~/.claude/skills/agent-builder/references/
cp README.md LICENSE CHANGELOG.md ~/.claude/skills/agent-builder/
```

Always verify with `diff -rq` after copying. Every file, every time.
