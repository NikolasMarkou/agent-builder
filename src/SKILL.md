---
name: agent-builder
description: Build AI agents from requirements. Covers single-agent, multi-agent, RAG, and production systems. Handles framework selection, pattern selection (topology, behavioral, data flow), state design, tool design, and full implementation. Defaults to Python with LangChain/LangGraph. Supports all major frameworks (CrewAI, Strands, OpenAI Agents SDK, Google ADK, Mastra, etc.). Use this skill whenever the user asks to build an agent, create an agentic system, implement a multi-agent workflow, design agent architecture, scaffold an agent project, or asks "how should I build an agent for X". Also trigger when the user mentions agent patterns, agent topology, ReAct loops, plan-and-execute, supervisor agents, swarm agents, handoffs, agent orchestration, or any agentic design question. Even if the user just says "build me an agent that does X" without mentioning frameworks, use this skill.
---

# Agent Builder

Build production-grade AI agents from requirements. Default stack: Python + LangChain v1.2.x + LangGraph v1.0.x.

## Design Axioms

Six principles that recur across every reference file. Apply them at every workflow step -- they are the difference between a demo and a production system. Most impactful for Moderate complexity and above.

| Axiom | Rule | Violated When |
|---|---|---|
| **Tiered escalation** | Cheap/deterministic first, LLM only for judgment, human as backstop | You send every query through the LLM when 60% could be a DB lookup |
| **Decompose** | Split complex tasks into simple, independent pieces | You ask an LLM to score 5 criteria in one call instead of 5 binary questions |
| **Model costs first** | Calculate token math at expected scale before writing code | You discover at launch that your $500/mo PoC costs $847K/mo in production |
| **Minimize context** | Send the minimum data needed; format matters (15-20pp accuracy swing) | You dump 2000-line files into context when 20 lines were relevant |
| **Calibrate on real data** | Build evals from real failures, not synthetic examples | Your benchmarks pass but production users hit edge cases you never tested |
| **Document failure modes** | Every pattern has known failures -- catalog and mitigate them upfront | Your loop runs forever because you didn't set a max iteration cap |

These axioms flow from a single root constraint: LLM inference is expensive, slow, and non-deterministic. Designing around this constraint is what separates production agents from demos.

## Workflow

Follow these steps in order. Do not skip the assessment phase.

**Decision State Block (DSB):** After completing each step, emit a DSB summarizing all decisions made so far. The DSB is your running state -- it prevents context loss between steps and ensures later steps respect earlier decisions. Format:

```
[DECISION STATE]
Complexity: {Simple | Moderate | Complex | Multi-agent | Batteries-included}
Needs agent: {yes | no -- if no, stop and recommend simpler approach}
Data requirements: {tabular | entity-resolution | text-search | none}
Deployment: {api-service | batch | embedded | none | TBD}
Production hardening: {yes | no | later}
Patterns: {topology} + {behavioral} + {data_flow} (after Step 2)
Framework: {name} (after Step 3)
References loaded: {list} (cumulative)
[/DECISION STATE]
```

**Tier routing:** Simple agents skip Steps 2-3 (go directly to Step 4 with `create_agent`). Moderate and above run all steps.

### Step 1: Assess Requirements

Before writing code, determine:

1. **What is the work to be done?** Map the workflow end-to-end. Every step, handoff, decision point.
2. **Does this actually need an agent?** Apply the technology selection hierarchy:
   - Rule-based automation (most reliable, cheapest)
   - Predictive analytics / traditional ML
   - LLM single-call with structured output
   - LLM with tools (simple agent)
   - Multi-agent orchestration (most flexible, most expensive)
   - Move up ONLY when the lower level cannot handle the variance.
3. **What is the complexity class?**

| Complexity | Characteristics | Default Approach |
|---|---|---|
| **Simple** | Single task, few tools, no branching, no persistence needed | `create_agent` (LangChain) |
| **Moderate** | Multiple tools, structured output, needs middleware (retry, moderation, fallback) | `create_agent` + middleware |
| **Complex** | Cycles, conditional branching, durable execution, human-in-the-loop, state persistence | LangGraph `StateGraph` |
| **Multi-agent** | Multiple specialized agents coordinating, handoffs, parallel work | LangGraph multi-agent patterns |
| **Batteries-included** | Complex tasks + filesystem + subagents + task planning + long-term memory | `create_deep_agent` (Deep Agents) |

4. **Requirements checklist** -- answer these explicitly to determine which references are needed later:
   - Does the agent process tabular data (spreadsheets, CSVs, database results)? If yes: `references/tabular-data.md` needed at Step 4.
   - Does the agent need entity resolution (matching/deduplication across sources, AML/KYC, knowledge graphs)? If yes: `references/entity-resolution.md` needed at Step 4.
   - Does the agent use text search, data filtering, or code navigation? If yes: `references/text-tools.md` needed at Step 4.
   - Does the agent retrieve and synthesize from a knowledge base or document corpus (RAG)? If yes: `references/retrieval.md` needed at Step 4.
   - Does the agent classify or route user input to different handlers? If yes: `references/structured-classification.md` needed at Step 4.
   - Does the task match a known scenario (deep research, customer support, code gen, data analysis, document processing, RAG, autonomous execution)? If yes: `references/scaffolding.md` needed at Steps 2 and 4.
   - Will the agent be deployed as a service? If yes: `references/deployment.md` needed at Step 5.
   - Does the agent need production hardening and evaluation? If yes: `references/production.md` + `references/evals.md` needed at Step 5.

**Emit DSB after Step 1.** Then apply tier routing:
- **Needs agent: no**: Recommend the appropriate non-agent approach:
  - *Rule-based*: if/else logic, lookup tables, regex, database queries. No LLM needed.
  - *Single LLM call*: `model.invoke()` with structured output for one-shot classification, extraction, or generation. No tools, no loops.
  - *LLM + structured output*: `model.with_structured_output(Schema)` for reliable extraction or routing without agent overhead.
  - Stop here. Do not proceed to Step 2.
- **Simple** complexity: skip to Step 4 (use `create_agent` — see `references/langchain-langgraph.md`). Emit DSB with `Patterns: N/A`, `Framework: LangChain (default)`.
- **Moderate and above**: continue to Step 2.

### Step 2: Select Patterns

Read `references/patterns.md` for the full pattern catalogue. Every agent system composes across three layers:

**Layer 1 - Topology** (how agents are wired):
- Parallel, Sequential, Loop, Router, Aggregator, Network, Hierarchical

**Layer 2 - Behavioral** (how agents reason):
- ReAct, Reflection, Plan-and-Execute, Generator-Critic, STORM, HITL, Tool Use

**Layer 3 - Data Flow** (how information moves):
- Map-Reduce, Prompt Chaining, Controlled Flow, Swarm, Subgraph

Quick selection:

| Task Shape | Topology | Behavioral | Data Flow |
|---|---|---|---|
| Simple tool-calling agent | Single node (no topology) | ReAct | N/A |
| Pipeline: ingest -> process -> output | Sequential | Tool Use at each step | Prompt Chaining |
| Research with iteration | Loop | STORM or Reflection | Controlled Flow |
| Multi-source aggregation | Parallel | ReAct per worker | Map-Reduce |
| Intent classification + routing | Router | ReAct per specialist | Controlled Flow | ← see `references/structured-classification.md` |
| Quality-gated generation | Loop | Generator-Critic | Controlled Flow |
| Team of specialists | Hierarchical | Plan-and-Execute (supervisor) + ReAct (workers) | Subgraph |
| Flexible peer-to-peer collaboration | Network | ReAct + Handoffs | Swarm |
| High-stakes with human approval | Any + HITL gates | Any + HITL | Any |

For scenario-specific recipes with complete topology diagrams, state shapes, guardrails, and failure modes, read `references/scaffolding.md`. Covers: deep research, customer support, code generation & review, data analysis, document processing, RAG, and autonomous task execution.

**Emit DSB after Step 2** with selected patterns filled in.

### Step 3: Select Framework

Default is **LangChain/LangGraph (Python)**. Read `references/langchain-langgraph.md` for implementation patterns.

Override the default only when:

| Condition | Use Instead | Read |
|---|---|---|
| AWS-native deployment, model-driven approach | Strands Agents | `references/strands.md` + `references/frameworks.md` |
| Role-based team, rapid prototyping | CrewAI | `references/frameworks.md` |
| OpenAI-only stack, voice/realtime | OpenAI Agents SDK | `references/frameworks.md` |
| Azure/.NET/Java enterprise | Semantic Kernel / MS Agent Framework | `references/frameworks.md` |
| Google Cloud native | Google ADK | `references/frameworks.md` |
| TypeScript/JS application | Mastra | `references/frameworks.md` |
| RAG-heavy, document processing | LlamaIndex | `references/frameworks.md` |
| Prompt optimization | DSPy | `references/frameworks.md` |
| Model-agnostic, persistent memory | Agno | `references/frameworks.md` |
| Lightweight, open-model focus | Smolagents | `references/frameworks.md` |

**Cross-validation gate:** Before proceeding, verify that the selected framework supports the patterns chosen in Step 2.

| Pattern | LangGraph | CrewAI | Strands | OpenAI SDK | Google ADK | Mastra | Semantic Kernel | DSPy | LlamaIndex | Agno | Smolagents |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Parallel (fan-out/fan-in) | Full | No | Full (Workflow) | No | Partial | Partial | Partial | No | No | No | No |
| Sequential | Full | Full | Full | No | Full | Full | Full | No | Full | Full | Full |
| Loop (conditional cycle) | Full | No | Full (Graph) | No | Partial | Partial | Partial | No | No | No | No |
| Router | Full | No | Full (Graph) | Partial | Full | Full | Full | No | No | Partial | No |
| Network / Swarm | Full | No | Full (Swarm) | Full | Partial | No | No | No | No | No | No |
| Hierarchical | Full | Full | Full | No | Partial | No | Full | No | No | No | No |
| HITL (interrupt/resume) | Full | No | No | No | No | No | No | No | No | No | No |

If the framework does not support a selected pattern, either change the framework or change the pattern. Do not proceed with a mismatch. Note: DSPy, LlamaIndex, Agno, and Smolagents are not orchestration frameworks — they handle prompt optimization, retrieval, model-agnostic agents, and lightweight tool use respectively. For orchestration patterns (Parallel, Loop, Network, HITL), pair them with LangGraph or another full-orchestration framework. See `references/frameworks.md` for details.

**Emit DSB after Step 3** with framework filled in.

### Step 4: Build

Read the appropriate reference file for your selected framework (from DSB), then implement. Load all references flagged in the DSB `References loaded` and `Data requirements` fields.

For system prompt and tool description design, read `references/prompt-structuring.md` -- covers delimiter format selection, prompt architecture, and model-specific guidance.

Load these based on DSB data requirements (identified in Step 1 checklist):
- **Tabular data**: read `references/tabular-data.md` -- serialization format selection, size-based strategies, token cost tradeoffs.
- **Entity resolution**: read `references/entity-resolution.md` -- blocking + matching + clustering pipeline, tiered matching, multi-agent ER, domain-specific patterns.
- **Text search / code navigation**: read `references/text-tools.md` -- three-layer search stack, tool-by-tool reference, agent-optimized search tools, cost math.
- **Knowledge base retrieval (RAG)**: read `references/retrieval.md` -- sparse/dense/hybrid retrieval, reranking, query transformation, corrective loops, GraphRAG, chunking strategies, agentic RAG architectures. For embedding model selection, evaluation protocols, and efficiency trade-offs, also read `references/embeddings.md`.
- **Intent classification / routing**: read `references/structured-classification.md` -- classifier schema design, enforcement mechanisms (prompt vs constrained decoding), confidence thresholding, handler routing, hierarchical classification for large class sets.
- **Scenario scaffolding**: read `references/scaffolding.md` -- if the task matches a known scenario (deep research, customer support, code gen, data analysis, document processing, RAG, autonomous execution), use the scenario-specific state shape, guardrails, and failure modes.

For the default LangChain/LangGraph stack, the build order is:

1. **Define State** - TypedDict or Pydantic model with reducers for accumulated fields
2. **Define Tools** - `@tool` decorated functions with type hints and docstrings
3. **Define Nodes** - Python functions: state in, partial state update out
4. **Define Edges** - Static edges for fixed flow, conditional edges for routing
5. **Wire the Graph** - `StateGraph` -> add nodes -> add edges -> compile
6. **Add Persistence** - Checkpointer for conversation memory, Store for long-term memory
7. **Add Human-in-the-Loop** - `interrupt()` at high-risk decision points
8. **Add Middleware** - Retry, fallback, moderation, summarization as needed

### Step 5: Production Hardening

Check the DSB: if `Production hardening: no`, skip this step. If `Deployment: api-service`, also read `references/deployment.md`.

Scale hardening to complexity (from DSB):
- **Simple/Moderate**: Focus on guardrails, cost modeling, basic observability. Skip resilience patterns and multi-agent failure modes.
- **Complex and above**: Full hardening -- all sections below apply.

Read `references/production.md` before deploying. Covers:
- Context engineering (context rot, token budget, three-artefact architecture)
- Tool design principles (minimize action space, shape to model capabilities, elicitation)
- Evaluation strategy (domain-specific evals, not generic benchmarks). Read `references/evals.md` for comprehensive evaluation guidance: frameworks, benchmarks, metrics, LLM-as-judge, safety evals, monitoring, and building eval pipelines. For LLM-as-judge implementation details, read `references/llm-as-judge.md`. For rubric design with binary decomposition, read `references/binary-evals.md`.
- Cost modeling (token math at scale)
- Observability (LangSmith tracing, structured logging, Prometheus metrics, Langfuse)
- Guardrails (input validation, output validation, tool permission scoping)
- Security hardening (input sanitization, rate limiting, JWT authentication)
- LLM service resilience (model registry, circular fallback, retry with exponential backoff)
- Failure modes catalogue and mitigation

For deployment — API serving, containerization, and monitoring stack — read `references/deployment.md`.

**Iteration:** If Step 4 or 5 reveals the selected pattern or framework cannot support a requirement, backtrack:
- **Pattern mismatch** (Step 4 fails): return to Step 2, select alternative pattern, re-run cross-validation gate.
- **Framework limitation** (Step 4 fails): return to Step 3, select alternative framework, re-run cross-validation gate.
- **Production gap** (Step 5 fails): add middleware/infrastructure rather than changing architecture. Only backtrack to Step 2 if the fundamental pattern is wrong.

Update the DSB with each revision. The DSB's `Patterns` and `Framework` fields are mutable until code is shipped.

---

## Code Templates

Read `references/langchain-langgraph.md` for ready-to-use code templates covering: simple agent (`create_agent`), ReAct with persistence (`StateGraph` + checkpointer), multi-agent swarm with handoffs (`create_swarm`), parallel fan-out/fan-in (`Send`), and human-in-the-loop with interrupt. For package versions and installation commands, see the Stack Architecture section in that same reference.

For Strands Agents, read `references/strands.md` for multi-agent patterns (Swarm, Graph, Workflow, Agents-as-Tools), deployment targets, A2A protocol, and migration guidance from LangGraph.

---

## Reference Files

Read these as needed -- each workflow step above specifies which references to load. Do NOT load all of them upfront.
