# Agent Builder

[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Skill](https://img.shields.io/badge/Skill-v1.6.1-green.svg)](CHANGELOG.md)
[![Sponsored by Electi](https://img.shields.io/badge/Sponsored%20by-Electi-red.svg)](https://www.electiconsulting.com)

**Stop guessing how to build AI agents. This skill does the thinking for you.**

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that guides you through building production-grade AI agents from requirements. It assesses complexity, selects the right patterns and framework, generates working code, and hardens it for production -- so you don't ship a demo that falls apart at scale.

The problem it solves: you ask an AI to "build me an agent" and get a generic ReAct loop with no persistence, no error handling, and no thought given to whether an agent was even the right choice. Agent Builder applies a structured 5-step workflow with Decision State Blocks tracking every decision: assess requirements, select patterns across three layers, pick the right framework, build with real code templates, and apply production hardening before deployment. Six design axioms -- tiered escalation, decomposition, cost modeling, context minimization, real-data calibration, and failure mode documentation -- are enforced at every step.

---

## Get Started in 60 Seconds

**Option 1 -- Zip package (recommended)**
Download the latest zip from [Releases](https://github.com/NikolasMarkou/agent-builder/releases) and unzip into your local skills directory:
```bash
unzip agent-builder-v*.zip -d ~/.claude/skills/
```

**Option 2 -- Single file**
Download `agent-builder-combined.md` from [Releases](https://github.com/NikolasMarkou/agent-builder/releases) and add it to Claude Code's Custom Instructions (Settings > Custom Instructions).

**Option 3 -- Clone the repo**
```bash
git clone https://github.com/NikolasMarkou/agent-builder.git ~/.claude/skills/agent-builder
```

Then ask Claude to build an agent -- or just say: **"build me an agent that does X"**

---

## How It Works

Five steps, six design axioms, and Decision State Blocks that track every decision across steps. Every choice grounded in requirements, not vibes. The right pattern, the right framework, the right level of complexity.

### Design Axioms

Six principles enforced at every workflow step:

| Axiom | Rule |
|---|---|
| **Tiered escalation** | Cheap/deterministic first, LLM only for judgment, human as backstop |
| **Decompose** | Split complex tasks into simple, independent pieces |
| **Model costs first** | Calculate token math at expected scale before writing code |
| **Minimize context** | Send the minimum data needed; format matters (15-20pp accuracy swing) |
| **Calibrate on real data** | Build evals from real failures, not synthetic examples |
| **Document failure modes** | Every pattern has known failures -- catalog and mitigate them upfront |

### Step 1: Assess Requirements

Map the workflow end-to-end. Determine if you actually need an agent (vs simpler automation). Classify complexity. A Decision State Block (DSB) is emitted after each step, tracking all decisions and preventing context loss.

| Complexity | Characteristics | Default Approach |
|---|---|---|
| **Simple** | Single task, few tools, no branching, no persistence needed | `create_agent` (LangChain) |
| **Moderate** | Multiple tools, structured output, needs middleware (retry, moderation, fallback) | `create_agent` + middleware |
| **Complex** | Cycles, conditional branching, durable execution, human-in-the-loop, state persistence | LangGraph `StateGraph` |
| **Multi-agent** | Multiple specialized agents coordinating, handoffs, parallel work | LangGraph multi-agent patterns |
| **Batteries-included** | Complex tasks + filesystem + subagents + task planning + long-term memory | `create_deep_agent` (Deep Agents) |

### Step 2: Select Patterns

Every agent system composes across three orthogonal layers:

| Layer | Patterns | What it controls |
|---|---|---|
| **Topology** | Parallel, Sequential, Loop, Router, Aggregator, Network, Hierarchical | How agents are wired |
| **Behavioral** | ReAct, Reflection, Plan-and-Execute, Generator-Critic, STORM, HITL, Tool Use | How agents reason |
| **Data Flow** | Map-Reduce, Prompt Chaining, Controlled Flow, Swarm, Subgraph | How information moves |

The pattern catalogue includes composition rules, common combinations (customer support, research, code review, document processing, financial analysis), and a failure mode catalogue with mitigations.

### Step 3: Select Framework

Default is **LangChain/LangGraph (Python)**. Override only when another framework is a clearly better fit:

| Condition | Use Instead |
|---|---|
| AWS-native deployment, model-driven approach | Strands Agents |
| Role-based team, rapid prototyping | CrewAI |
| OpenAI-only stack, voice/realtime | OpenAI Agents SDK |
| Azure/.NET/Java enterprise | Semantic Kernel / MS Agent Framework |
| Google Cloud native | Google ADK |
| TypeScript/JS application | Mastra |
| RAG-heavy, document processing | LlamaIndex |
| Prompt optimization | DSPy |
| Model-agnostic, persistent memory | Agno |
| Lightweight, open-model focus | Smolagents |

A cross-validation gate verifies that the selected framework supports the patterns chosen in Step 2 before proceeding. The framework guide includes 18 use-case comparisons and head-to-head tables.

### Step 4: Build

Working code templates for 5 common patterns: simple agent, ReAct with persistence, multi-agent swarm with handoffs, parallel fan-out/fan-in, and human-in-the-loop with interrupt. Plus full implementation reference for the default stack covering state management, edges, streaming, memory, middleware, and MCP integration.

### Step 5: Production Hardening

Before deploying, the skill walks through:

| Area | What it covers |
|---|---|
| **Context Engineering** | Context rot, token budget, three-artefact architecture, compression strategies |
| **Tool Design** | Minimize action space, shape to model capabilities, progressive disclosure |
| **Evaluation** | Frameworks, benchmarks, metrics, LLM-as-judge, safety evals, monitoring, eval pipelines |
| **Cost Modeling** | Token math at scale, cost reduction levers |
| **Observability** | LangSmith tracing, structured logging, Prometheus metrics, Langfuse |
| **Security** | Input sanitization, rate limiting, JWT authentication |
| **Resilience** | Model registry, circular fallback, retry with exponential backoff, connection pooling |
| **Deployment** | API serving (FastAPI), streaming, Docker, monitoring stack, long-term memory |
| **Guardrails** | Input/output validation, tool permission scoping, MCP security |
| **Failure Modes** | 10 production failure modes with mitigations |

---

## When to Use This

| Use it | Skip it |
|--------|---------|
| Building any AI agent from scratch | Simple single LLM call with no tools |
| Choosing between agent frameworks | Already know exactly what to build |
| Designing multi-agent architectures | Non-agentic ML/data science tasks |
| Production-hardening an existing agent | |
| Selecting the right patterns for a use case | |

Trigger phrases: *"build me an agent"*, *"create an agent"*, *"design agent architecture"*, *"what framework should I use"*, *"make this production-ready"*, *"scaffold an agent project"*

---

## Contributing

### Build and Package

```bash
# Windows (PowerShell)
.\build.ps1 package          # Create zip package
.\build.ps1 package-combined # Create single-file skill
.\build.ps1 validate         # Validate structure
.\build.ps1 clean            # Clean build artifacts

# Unix / Linux / macOS
make package                 # Create zip package
make package-combined        # Create single-file skill
make validate                # Validate structure
make clean                   # Clean build artifacts
```

### Project Structure

```
agent-builder/
├── README.md                 # This file
├── CLAUDE.md                 # AI assistant guidance for contributing
├── CHANGELOG.md              # Version history
├── LICENSE                   # GNU GPLv3
├── VERSION                   # Single source of truth for version number
├── Makefile                  # Unix/Linux/macOS build
├── build.ps1                 # Windows PowerShell build
└── src/
    ├── SKILL.md              # Core skill -- the 5-step workflow and code templates
    └── references/
        ├── patterns.md           # Pattern catalogue (topology, behavioral, data flow)
        ├── langchain-langgraph.md # Default stack implementation reference
        ├── frameworks.md          # Alternative framework guidance (10 frameworks)
        ├── production.md          # Production hardening reference
        ├── deployment.md          # Deployment: API serving, Docker, monitoring stack, memory
        ├── evals.md               # Evaluation reference (frameworks, benchmarks, metrics, tooling)
        ├── prompt-structuring.md  # Prompt structure: delimiters, 7-block template, techniques
        ├── tabular-data.md        # Tabular data serialization: formats, size strategies, token costs
        ├── llm-as-judge.md        # LLM-as-Judge: biases, calibration, rubrics, production deployment
        ├── binary-evals.md        # Binary evaluation rules: CheckEval, boolean rubrics, scoring
        ├── entity-resolution.md   # Entity resolution: blocking, matching, clustering, multi-agent ER
        ├── text-tools.md            # Text tools for agents: search stack, ripgrep, ast-grep, jq, sqlite3
        ├── retrieval.md             # Text retrieval: sparse/dense/hybrid search, reranking, RAG, GraphRAG
        └── structured-classification.md # Structured classification: intent detection, schema design, routing
```

---

## Sponsored by

This project is sponsored by **[Electi Consulting](https://www.electiconsulting.com)** -- a technology consultancy specializing in AI, blockchain, cryptography, and data science. Founded in 2017 and headquartered in Limassol, Cyprus, with a London presence, Electi combines academic rigor with enterprise-grade delivery across clients including the European Central Bank, US Navy, and Cyprus Securities and Exchange Commission.

---

## License

[GNU General Public License v3.0](LICENSE)
