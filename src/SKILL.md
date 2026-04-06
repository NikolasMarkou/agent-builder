---
name: agent-builder
description: >-
  Build, review, troubleshoot, and optimize AI agents. Covers single-agent, multi-agent, RAG, and production systems. Handles framework selection, pattern selection (topology, behavioral, data flow), state design, tool design, and full implementation. Defaults to Python with LangChain/LangGraph. Supports all major frameworks (CrewAI, Strands, OpenAI Agents SDK, Google ADK, Mastra, etc.). Use this skill whenever the user asks to build an agent, create an agentic system, implement a multi-agent workflow, design agent architecture, scaffold an agent project, or asks "how should I build an agent for X". Also trigger when the user mentions agent patterns, agent topology, ReAct loops, plan-and-execute, supervisor agents, swarm agents, handoffs, agent orchestration, or any agentic design question. Also trigger for non-build operations - reviewing agent architecture, troubleshooting agent issues (hallucination, loops, cost, latency), optimizing agent performance or prompts, extending existing agents with new capabilities, or migrating between frameworks. Even if the user just says "build me an agent that does X" without mentioning frameworks, use this skill.
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

## Query Router

Before starting, classify the user's request. Not every query is "build a new agent."

| If the user is asking to... | Route to |
|---|---|
| Build, create, design, or scaffold a new agent | **Build Workflow** (Steps 1-5 below) |
| Review, audit, or assess an existing agent's architecture | **Review Workflow** (below) |
| Fix a broken agent, debug issues, diagnose failures | **Troubleshoot Workflow** (below) |
| Reduce cost, improve performance, optimize prompts | **Optimize Workflow** (below) |
| Add a capability to an existing agent (memory, HITL, streaming, tools, evals) | **Extend** — go to Step 4 (Build) + Step 5 (Harden), skip Steps 1-3. Read the relevant reference for the capability being added. |
| Choose a framework or pattern (no existing agent) | **Build Workflow** Steps 1-3 |
| Migrate or convert an agent from one framework to another | **Review Workflow** (map current architecture, Steps R1-R2), then **Build Workflow** Steps 3-5 (select new framework, rebuild, harden) |

**Mixed requests** ("build a new agent and review my existing one"): handle the build first, then run the review workflow on the existing agent.

**Default**: If unclear, ask the user whether they are building something new or working with an existing agent.

---

## Build Workflow

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
   - Does the agent retrieve and synthesize from a knowledge base or document corpus (RAG)? If yes: `references/retrieval.md` needed at Step 4. If queries require cross-document reasoning or evidence chaining (multi-hop): also `references/multi-hop-rag.md`.
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
| Research with iteration | Loop | Reflection | Controlled Flow |
| Multi-source aggregation | Parallel | ReAct per worker | Map-Reduce |
| Intent classification + routing | Router | ReAct per specialist | Controlled Flow | ← see `references/structured-classification.md` |
| Quality-gated generation | Loop | Generator-Critic | Controlled Flow |
| Team of specialists | Hierarchical | Plan-and-Execute (supervisor) + ReAct (workers) | Subgraph |
| Flexible peer-to-peer collaboration | Network | ReAct + Handoffs | Swarm |
| High-stakes with human approval | Any + HITL gates | Any + HITL | Any |

**Composition recipes:** Some tasks require patterns from multiple layers composed together. For example, STORM (deep research) composes Parallel + Loop (topology) with ReAct (behavioral) and Map-Reduce (data flow) -- see `references/patterns.md` §2.5. Do not treat compositions as single-layer pattern choices; select each layer independently and verify compatibility.

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
| Prompt optimization | DSPy | `references/dspy.md` + `references/frameworks.md` |
| Model-agnostic, persistent memory | Agno | `references/frameworks.md` |
| Lightweight, open-model focus | Smolagents | `references/frameworks.md` |

**Cross-validation gate:** Before proceeding, verify that the selected framework supports the patterns chosen in Step 2.

| Pattern | LangGraph | CrewAI | Strands Agents | OpenAI Agents SDK | Google ADK | Mastra | Semantic Kernel / MS | DSPy | LlamaIndex | Agno | Smolagents |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Parallel (fan-out/fan-in) | Full | No | Full (Workflow) | No | Partial | Partial | Partial | No | No | No | No |
| Sequential | Full | Full | Full | No | Full | Full | Full | No | Full | Full | Full |
| Loop (conditional cycle) | Full | No | Full (Graph) | No | Partial | Partial | Partial | No | No | No | No |
| Router | Full | No | Full (Graph) | Partial | Full | Full | Full | No | No | Partial | No |
| Network / Swarm | Full | No | Full (Swarm) | Full | Partial | No | No | No | No | No | No |
| Hierarchical | Full | Full | Full | No | Partial | No | Full | No | No | No | No |
| HITL (interrupt/resume) | Full | No | No | No | No | No | No | No | No | No | No |

If the framework does not support a selected pattern, either change the framework or change the pattern. Do not proceed with a mismatch. Note: DSPy, LlamaIndex, Agno, and Smolagents are not orchestration frameworks — they handle prompt optimization, retrieval, model-agnostic agents, and lightweight tool use respectively. For orchestration patterns (Parallel, Loop, Network, HITL), pair them with LangGraph or another full-orchestration framework. The `references/frameworks.md` selection matrix also references external frameworks not covered in depth (Haystack, AutoGen, Vercel AI SDK, Letta/MemGPT) — see footnotes in that file if a use case aligns.

**Emit DSB after Step 3** with framework filled in.

### Step 4: Build

Read the appropriate reference file for your selected framework (from DSB), then implement. Load all references flagged in the DSB `References loaded` and `Data requirements` fields.

For system prompt and tool description design, read `references/prompt-structuring.md` -- covers delimiter format selection, prompt architecture, and model-specific guidance.

Load these based on DSB data requirements (identified in Step 1 checklist):
- **Tabular data**: read `references/tabular-data.md` -- serialization format selection, size-based strategies, token cost tradeoffs.
- **Entity resolution**: read `references/entity-resolution.md` -- blocking + matching + clustering pipeline, tiered matching, multi-agent ER, domain-specific patterns.
- **Text search / code navigation**: read `references/text-tools.md` -- three-layer search stack, tool-by-tool reference, agent-optimized search tools, cost math.
- **Knowledge base retrieval (RAG)**: read `references/retrieval.md` -- sparse/dense/hybrid retrieval, reranking, query transformation, corrective loops, GraphRAG, chunking strategies, agentic RAG architectures. For multi-hop queries (cross-document reasoning, entity-relationship traversal, evidence chain construction), also read `references/multi-hop-rag.md`. For embedding model selection, evaluation protocols, and efficiency trade-offs, also read `references/embeddings.md`.
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
- **Complex**: Full hardening -- all sections below apply.
- **Multi-agent**: Full hardening + multi-agent failure modes (supervisor saturation, handoff loops, agent identity drift). Read `references/patterns.md` §Failure Mode Catalogue for multi-agent-specific entries.
- **Batteries-included**: Full hardening + deep agent monitoring (subagent cost tracking, task planning divergence, long-term memory consistency). Set budget caps and observe subagent spawn depth.

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

---

## Review Workflow

Structured architecture review of an existing agent. Read the agent's code first, then work through these steps.

### Step R1: Map the Current Architecture

Identify what the agent currently uses:
1. **Topology**: How are agents/nodes wired? (Single agent, Sequential, Parallel, Router, Hierarchical, Network?) Compare against `references/patterns.md` topology patterns.
2. **Behavioral pattern**: How does each agent reason? (ReAct, Plan-and-Execute, Reflection, Generator-Critic, STORM?) Compare against `references/patterns.md` behavioral patterns.
3. **Data flow**: How does information move? (Prompt Chaining, Map-Reduce, Controlled Flow, Swarm, Subgraph?) Compare against `references/patterns.md` data flow patterns.
4. **Framework**: What framework is used? Cross-check against `references/frameworks.md` for known limitations.

### Step R2: Check Pattern Fit

Using the pattern selection decision framework in `references/patterns.md`:
- Does the chosen topology match the task shape? (e.g., using Hierarchical when Sequential suffices is over-engineering)
- Does the chosen behavioral pattern match the reasoning requirements? (e.g., ReAct for a task that needs upfront planning is a mismatch)
- Are patterns composed correctly? Check composition rules in `references/patterns.md` §Pattern Composition Rules.
- Does the task match a known scenario? Compare against `references/scaffolding.md` -- if yes, check alignment with the scenario recipe.

### Step R3: Production Readiness Audit

Run through the Deployment Checklist in `references/production.md` §Deployment Checklist:
- Are max iteration caps set on all loops?
- Are concurrency caps on all parallel fan-outs?
- Is there error handling at every node?
- Are HITL gates at high-risk decision points?
- Is context budget defined and enforced?
- Is tool count minimized?
- Is cost model computed?

Check failure modes: compare the agent's patterns against the Failure Mode Catalogue in `references/patterns.md` §Failure Mode Catalogue. Are known failure modes mitigated?

### Step R4: Deliver Review

Present findings as:
1. **Architecture summary** (topology + behavioral + data flow, with pattern names)
2. **Pattern fit assessment** (correct / over-engineered / under-engineered / mismatch, with reasoning)
3. **Production gaps** (specific items from the checklist that are missing)
4. **Failure mode exposure** (which known failure modes are unmitigated)
5. **Recommendations** (prioritized by impact, with reference pointers for implementation)

---

## Troubleshoot Workflow

Symptom-based diagnostic for broken or underperforming agents. Start from the symptom, not the code.

### Step T1: Identify the Symptom

| Symptom | Likely Root Cause | Read |
|---|---|---|
| Agent hallucinates or invents facts | Context rot, missing grounding, no faithfulness check | `references/production.md` §Context Engineering, `references/retrieval.md` §Post-Retrieval |
| Agent loops forever | Missing iteration cap, unreachable quality threshold, gap detection diverging | `references/patterns.md` §Failure Mode Catalogue (infinite loop) |
| Agent picks wrong tools | Too many tools, unclear tool descriptions, no progressive disclosure | `references/production.md` §Tool Design Principles |
| Agent is too slow | Sequential when Parallel possible, unnecessary loop iterations, no caching | `references/patterns.md` §1.1 Parallel, `references/deployment.md` §Streaming |
| Agent costs too much | No model routing, no context compression, unbounded fan-out, no caching | `references/production.md` §Cost Modeling |
| Agent loses context mid-conversation | No checkpointing, context window overflow, no summarization | `references/production.md` §Context Engineering, `references/langchain-langgraph.md` §Persistence |
| Agent routes to wrong specialist | Classifier quality, overlapping categories, no fallback | `references/structured-classification.md`, `references/patterns.md` §1.4 Router |
| RAG returns irrelevant results | Wrong retrieval method, bad chunking, no reranking, stale embeddings | `references/retrieval.md`, `references/embeddings.md` |
| RAG fails on multi-hop questions | Single-hop retrieval for cross-document queries, no evidence chaining, bad decomposition | `references/multi-hop-rag.md`, `references/retrieval.md` §GraphRAG |
| Agent crashes on resume | Stale checkpoints, missing state validation | `references/patterns.md` §Failure Mode Catalogue (stale state) |
| Prompts produce inconsistent output | No structured output, poor delimiter choice, position bias | `references/prompt-structuring.md` |

### Step T2: Diagnose

1. Read the relevant reference(s) from the table above.
2. Check the agent's code against the specific failure mode and its documented mitigation.
3. If the symptom doesn't match the table, check the full Failure Mode Catalogue in `references/patterns.md` and Production Failure Modes in `references/production.md`.

### Step T3: Fix

Apply the documented mitigation. For each fix:
- State what the root cause was.
- State what the fix does and why.
- Reference the specific pattern, guideline, or checklist item that the fix implements.

---

## Optimize Workflow

Prioritized optimization for cost, performance, and prompt quality. Work through in order -- earlier items have higher ROI.

### Step O1: Cost Optimization (highest ROI)

Read `references/production.md` §Cost Modeling. Check in order:

1. **Model routing**: Is a flagship model used for tasks a cheaper model could handle? Apply tiered escalation (Design Axiom 1). Implement `ModelFallbackMiddleware` or custom routing.
2. **Context size**: Is unnecessary data in the context? Apply context compression (`SummarizationMiddleware`), tool output truncation, semantic deduplication. Read `references/production.md` §Context Engineering.
3. **Caching**: Are identical or near-identical queries re-processed? Add tool result caching, embedding similarity caching (`references/retrieval.md` §cache by embedding similarity).
4. **Loop efficiency**: Are loops running more iterations than needed? Tighten quality thresholds, add early exit conditions.
5. **Fan-out control**: Are parallel branches unbounded? Cap concurrency, batch fan-out.
6. **Batch processing**: Are realtime paths used for non-realtime workloads? Switch to Batch API (typically 50% cheaper).

### Step O2: Performance Optimization

1. **Parallelization**: Are sequential steps truly dependent? Independent steps should run in parallel (`references/patterns.md` §1.1 Parallel).
2. **Streaming**: Is the user waiting for full completion? Add streaming (`references/deployment.md` §Streaming, `references/langchain-langgraph.md` §Streaming).
3. **Pre-computation**: Can schemas, embeddings, or static context be cached at startup rather than computed per-request?
4. **Retrieval tuning**: For RAG agents, check hybrid retrieval, reranking, and chunking strategies (`references/retrieval.md`).

### Step O3: Prompt Optimization

1. **Structure audit**: Check prompt structure against `references/prompt-structuring.md` -- delimiter format, block ordering, position bias.
2. **Systematic optimization**: For prompts that need tuning beyond manual editing, use DSPy (`references/dspy.md`) to optimize prompts programmatically against evaluation metrics.
3. **Tabular data**: If the agent processes tables/spreadsheets, check serialization format against `references/tabular-data.md` -- format choice alone swings accuracy 15-20pp.
