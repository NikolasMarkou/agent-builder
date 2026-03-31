# Strands Agents Reference

Implementation reference for building agents with Strands Agents SDK. Use when the framework decision (Step 3) selects Strands over the default LangChain/LangGraph stack.

## Table of Contents

1. [When This Reference Applies](#when-this-reference-applies)
2. [Core Architecture](#core-architecture)
3. [Model Provider Selection](#model-provider-selection)
4. [Tool Design](#tool-design)
5. [Multi-Agent Patterns](#multi-agent-patterns)
6. [Memory and Session State](#memory-and-session-state)
7. [Structured Output](#structured-output)
8. [Observability](#observability)
9. [Deployment](#deployment)
10. [A2A Protocol](#a2a-protocol)
11. [Agent SOPs](#agent-sops)
12. [Evaluation](#evaluation)
13. [Production Project Structure](#production-project-structure)
14. [Pattern Mapping](#pattern-mapping)
15. [Migration from LangGraph](#migration-from-langgraph)

---

## When This Reference Applies

Use Strands when ALL of these hold:
- AWS-native deployment (Lambda, Fargate, EKS, or AgentCore)
- Model-driven approach preferred (trust the LLM to plan, no explicit state machine needed)
- Minimal framework overhead wanted
- Python or TypeScript (TS is preview)

Do NOT use Strands when:
- You need explicit state machines with durable checkpointing (use LangGraph)
- You need fine-grained control over every state transition (use LangGraph)
- You need HITL interrupt/resume semantics (use LangGraph — Strands has no built-in HITL interrupt)

---

## Core Architecture

Every Strands agent has three components:

| Component | Role | Design Principle |
|---|---|---|
| **Model Provider** | Reasoning engine | Choose based on deployment target and cost. Bedrock for AWS, direct API for others. |
| **System Prompt** | Agent role, behavior, constraints | Apply prompt structuring from `references/prompt-structuring.md`. |
| **Toolbelt** | Functions the agent can call | Apply tool design from `references/production.md`. Minimize action space. |

**Agentic loop:** The LLM iteratively reasons, selects a tool, executes it, incorporates the result, and decides the next step — until it reaches a final answer. No developer-defined graph or state machine. The model IS the control flow.

**Key implication:** Agent quality depends heavily on model capability and prompt engineering. Invest more in system prompt design and tool descriptions than you would with an explicit-graph framework.

---

## Model Provider Selection

Strands is model-agnostic. Supported providers:

| Provider | Use When | Notes |
|---|---|---|
| **Amazon Bedrock** | AWS deployment (default) | Native integration, IAM auth, no API keys in code |
| **Anthropic Direct** | Need latest Claude models, non-AWS | Direct API, requires ANTHROPIC_API_KEY |
| **OpenAI** | GPT-4o or o-series needed | Requires OPENAI_API_KEY |
| **Ollama** | Local development, air-gapped | No cloud dependency, limited model capability |
| **LiteLLM** | Multi-provider routing | Unified interface across 100+ providers |
| **Community** | Cohere, xAI, Fireworks, NVIDIA NIM, vLLM, MLX, SGLang, Baseten | Via community-contributed provider packages |

**Selection principle:** Default to Bedrock for AWS production. Use direct API for development or when you need the latest model versions before Bedrock availability.

---

## Tool Design

### Custom Tools

Any Python function with type hints and a docstring becomes a tool via the `@tool` decorator. The docstring is exposed to the LLM as the tool description.

**Design rules** (same as `references/production.md` tool design):
- One tool = one action. Don't combine "search and summarize" into one tool.
- Docstring is the tool's interface to the LLM. Be specific about inputs, outputs, and constraints.
- Type hints are mandatory — they define the tool's parameter schema.
- Return strings. The LLM consumes the output as text.

### Pre-built Tools

Strands provides 20+ pre-built tools: calculator, file I/O, HTTP requests, shell, editor, image reader, Python REPL, and AWS-specific tools (Bedrock Knowledge Bases retrieval, Nova Canvas image generation).

**When to use pre-built vs custom:** Use pre-built for standard operations (file I/O, HTTP, math). Build custom tools for domain-specific logic, external API integrations, and database access.

### MCP Integration

Strands has first-class MCP support — connect to any MCP server (stdio or streamable HTTP) and expose its tools to the agent. This is the primary mechanism for integrating with external services and data sources.

**When to use MCP:** When tools are provided by external services, when you want tool reusability across agents, or when integrating with the broader MCP ecosystem.

### Semantic Tool Retrieval

For agents with large tool sets (100+), use semantic search to dynamically select relevant tools per request instead of describing all tools to the model. This reduces context window usage and improves tool selection accuracy.

**When to use:** When tool count exceeds what fits comfortably in context (typically >30 tools), or when tool relevance varies significantly by query.

---

## Multi-Agent Patterns

Strands provides three built-in multi-agent orchestration patterns plus the agents-as-tools pattern:

### Agents as Tools (Supervisor)

Wrap specialist agents as `@tool`-decorated functions. The orchestrator agent calls them like any other tool.

| Aspect | Guidance |
|---|---|
| **When to use** | Known specialist delegation, modular design, clear domain boundaries |
| **Orchestrator prompt** | Must describe each specialist's capability and when to delegate |
| **Specialist lifecycle** | Each specialist is instantiated per invocation (stateless) or shared (stateful) |
| **Error handling** | Specialist failures surface as tool errors to the orchestrator |

### Swarm (Emergent Coordination)

Agents hand off to each other dynamically via `strands.multiagent.Swarm`. Each agent decides who to hand off to next based on the task state.

| Aspect | Guidance |
|---|---|
| **When to use** | Complex open-ended tasks where optimal agent sequence is unknown upfront |
| **Handoff mechanism** | Agent response includes `agentId` (next agent), `message` (instructions), `context` (structured data) |
| **Entry agent** | Required — the first agent that receives the initial task |
| **Shared state** | Via `invocation_state` dict — not exposed to LLM, accessible by all agents |
| **Termination** | Agent omits `agentId` to end and return final response |
| **Failure mode** | Infinite handoff loops. Mitigate with max handoff count or timeout. |

**Maps to:** Network topology + Swarm data flow pattern from `references/patterns.md`.

### Graph (Deterministic Routing)

Directed graph where agents are nodes and edges define routing. Supports conditional edges, DAG and cyclic topologies.

| Aspect | Guidance |
|---|---|
| **When to use** | Conditional routing, approval gates, retry logic, ordered processing steps |
| **Node types** | Agent nodes, custom function nodes, nested multi-agent systems |
| **Edge types** | Static (always follow) or conditional (Python function evaluates state) |
| **Topology** | DAG for pipelines, cyclic for feedback loops and iterative refinement |
| **State passing** | Output from one node becomes input to connected nodes |

**Maps to:** Router/Loop topology + Controlled Flow data flow pattern from `references/patterns.md`.

### Workflow (Dependency-Based Parallelism)

Developer-defined task graph with explicit dependencies. Independent branches run in parallel automatically.

| Aspect | Guidance |
|---|---|
| **When to use** | Predictable pipelines, batch processing, tasks with clear dependency ordering |
| **Task definition** | Each task is an agent + name. Dependencies define execution order. |
| **Parallelism** | Automatic — tasks without mutual dependencies run concurrently |
| **Failure mode** | Upstream task failure blocks all dependents. Design idempotent tasks. |

**Maps to:** Parallel topology + Map-Reduce data flow pattern from `references/patterns.md`.

### Pattern Selection (Strands-Specific)

| Task Shape | Strands Pattern | Topology Equivalent |
|---|---|---|
| Simple tool-calling | Single Agent | Single node |
| Known specialist delegation | Agents as Tools | Hierarchical |
| Open-ended multi-step | Swarm | Network |
| Conditional routing / gates | Graph | Router / Loop |
| Fixed pipeline with parallelism | Workflow | Parallel / Sequential |

---

## Memory and Session State

| Memory Type | Mechanism | Use When |
|---|---|---|
| **Conversational** | Built-in (default) — messages persist within session | Multi-turn interactions |
| **Persistent sessions** | SessionManager with session ID | Cross-invocation memory, user-specific context |
| **Remote session** | Community packages (Valkey/Redis, AgentCore Memory) | Production persistence at scale |
| **Shared agent state** | `invocation_state` dict in multi-agent patterns | Passing non-LLM data between agents |

**Key distinction:** Conversational memory is exposed to the LLM. Shared state (`invocation_state`) is NOT exposed to the LLM — use it for metadata, configuration, and inter-agent coordination data.

---

## Structured Output

Strands supports Pydantic model-based structured output via the `output_schema` parameter. The agent's response is parsed and validated against the schema automatically.

**When to use:** Classification, extraction, structured report generation, any case where you need typed output rather than free-form text. Apply schema design principles from `references/structured-classification.md`.

---

## Observability

Strands uses OpenTelemetry (OTEL) natively:

| Primitive | What It Captures |
|---|---|
| **Traces** | End-to-end request flow, all spans from prompt to final response |
| **Spans** | Individual model calls, tool invocations, agent handoffs |
| **Metrics** | Token usage, latency, tool invocation counts, error rates |
| **Logs** | Standard Python logging, agent reasoning steps |

**Backend integration:** Any OTEL-compatible backend — Langfuse, AWS X-Ray, CloudWatch, Jaeger, Datadog, Grafana. Configure via OTEL environment variables.

**Trace attributes:** Set `session.id`, `user.id`, and custom tags on agent creation for production traceability.

**Key advantage over custom observability:** OTEL is a standard — no vendor lock-in, and spans propagate across distributed agent architectures (including A2A calls).

---

## Deployment

### AWS Lambda (Serverless)

Best for event-driven, low-traffic, or bursty workloads. Agent is instantiated in the handler. Cold starts are the main concern — keep the agent lightweight.

### Amazon Bedrock AgentCore (Managed Runtime)

Secure, serverless runtime purpose-built for AI agents. Supports long-running tasks (up to 8 hours), async tool execution, and tool interoperability (MCP, A2A, API Gateway). Includes IAM/Cognito/OAuth identity and native CloudWatch + OTEL observability.

**When to use:** Production enterprise agents that need managed infrastructure, security, and observability without DIY setup.

### Container (Docker / Kubernetes / Fargate)

Standard containerized deployment. Use for persistent agents, high-traffic workloads, or when you need custom infrastructure.

### Deployment Selection

| Requirement | Deployment Target |
|---|---|
| Event-driven, bursty | Lambda |
| Enterprise, managed, long-running | AgentCore |
| Custom infra, high traffic | Container (EKS/Fargate) |
| Development / testing | Local (Ollama or direct API) |

---

## A2A Protocol

Agent-to-Agent (A2A) protocol enables cross-framework agent interoperability. A Strands agent can expose itself as an A2A endpoint and call remote A2A agents from other frameworks.

| Capability | Use When |
|---|---|
| **A2A Server** | Expose a Strands agent as a network service callable by any A2A-compatible client |
| **A2A Client** | Call remote agents (any framework) from within a Strands agent via `@tool` |

**When to use:** Microservice agent architectures, cross-team agent interop, gradual migration between frameworks, polyglot agent systems.

**When NOT to use:** All agents are in the same process/framework. A2A adds network overhead and failure modes.

---

## Agent SOPs

Standard Operating Procedures (SOPs) are natural language workflows that guide agents through complex multi-step tasks. Strands can embed SOPs as system prompts via the `strands-agents-sop` package.

**Built-in SOPs:** code-assist, code-task-generator, codebase-summary, product design document.

**When to use:** Repetitive multi-step tasks that need consistency. SOPs are more maintainable than detailed system prompts for complex workflows.

---

## Evaluation

Strands provides `strands-agents-evals` for agent evaluation:

| Eval Mode | Use When |
|---|---|
| **Exact match** | Deterministic outputs (math, lookups) |
| **LLM-as-judge** | Subjective quality (summaries, analysis) |
| **Tool-specific** | Verify correct tool selection and parameter passing |
| **Manual** | Human review for edge cases and safety |

Apply evaluation principles from `references/evals.md` and `references/llm-as-judge.md`.

---

## Production Project Structure

Recommended layout for production Strands agents:

```
my-strands-agent/
├── agents/              # Agent definitions (orchestrator + specialists)
├── tools/               # @tool decorated domain functions
├── prompts/             # System prompts (separate from code)
├── config/              # Model IDs, region, temperature, etc.
├── observability/       # OTEL setup, trace attributes
├── tests/               # Eval test cases
├── Dockerfile
├── requirements.txt
└── main.py              # Entry point (OTEL init → build agent → run)
```

**Key practices:**
- Initialize OTEL before agent creation (telemetry captures everything)
- Externalize system prompts (easier to iterate without code changes)
- Separate tool definitions from agent definitions (tools are reusable across agents)
- Config-driven model selection (switch providers without code changes)

---

## Failure Modes

| Failure Mode | Cause | Symptoms | Mitigation |
|---|---|---|---|
| **Infinite handoff loops** | Swarm agents hand off to each other without termination condition | CPU/token burn, no response returned | Set `max_handoffs` or total iteration cap; add cycle detection in handoff logic |
| **Upstream task blocking** | Workflow task fails, blocking all dependent tasks | Workflow hangs; downstream agents never execute | Design idempotent tasks; add timeout per task; implement fallback paths for non-critical dependencies |
| **Model-driven flow unpredictability** | No explicit state machine — model decides next action | Non-deterministic execution paths; hard to reproduce bugs | Use Graph pattern for critical flows; add `@tool` guards that validate preconditions; log full reasoning traces via OTEL |
| **Tool schema drift** | Tool function signatures change but system prompt references stale descriptions | Agent calls tools with wrong arguments; silent failures | Auto-generate tool descriptions from docstrings; version tool schemas; test tool calls in CI |
| **Session state loss** | SessionManager not configured or storage backend fails | Agent loses context across turns; repeated questions | Always configure persistent SessionManager in production; health-check storage backend at startup |
| **Lambda cold start latency** | Large model initialization on first invocation | First request takes 5-15s; user-facing timeout | Use provisioned concurrency; keep model initialization outside handler; use lighter models for latency-sensitive paths |

---

## Pattern Mapping

How Strands patterns map to the agent-builder pattern catalogue (`references/patterns.md`):

| Agent-Builder Pattern | Strands Implementation | Notes |
|---|---|---|
| **Parallel** (fan-out/fan-in) | Workflow with independent tasks | Automatic parallelism via dependency graph |
| **Sequential** | Workflow with linear dependencies, or single agent | Linear task chain |
| **Loop** (conditional cycle) | Graph with cyclic edges | Condition functions control loop exit |
| **Router** | Graph with conditional edges | Python functions evaluate routing conditions |
| **Network / Swarm** | Swarm | Agent-driven handoffs, emergent coordination |
| **Hierarchical** | Agents as Tools | Orchestrator delegates to specialist tools |
| **HITL** | Not built-in | Implement manually via tool that blocks for human input |
| **ReAct** | Default agent behavior | The agentic loop IS ReAct |
| **Map-Reduce** | Workflow (parallel branches → aggregation agent) | Fan-out via independent tasks, fan-in via dependent task |
| **Prompt Chaining** | Sequential Workflow or agents-as-tools chain | Each agent processes and passes to next |
| **Swarm** (data flow) | Swarm (multi-agent) | Direct mapping |

---

## Migration from LangGraph

When migrating existing LangGraph agents to Strands:

| LangGraph Concept | Strands Equivalent |
|---|---|
| `StateGraph` | No equivalent — model drives flow |
| `TypedDict` state | `invocation_state` for shared data, Pydantic `output_schema` for structured output |
| Conditional edges | Graph pattern with condition functions |
| `Send()` for fan-out | Workflow with independent tasks |
| `interrupt()` for HITL | No built-in equivalent — implement via blocking tool |
| Checkpointer | SessionManager for session persistence |
| `create_react_agent` | `Agent()` (default behavior) |
| `create_swarm` | `Swarm()` |
| Node functions | Agents or custom Graph nodes |
| `@tool` decorator | `@tool` decorator (same concept, different import) |
| MCP via adapters | Native MCP support (`MCPClient`) |

**What you lose:** Durable execution with checkpointing, explicit state machine visualization, built-in HITL interrupt/resume, fine-grained state transitions.

**What you gain:** Minimal boilerplate, model-driven planning, native AWS deployment (Lambda/AgentCore), A2A protocol, native OTEL, native MCP.
