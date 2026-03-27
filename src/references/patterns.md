# Agent Patterns Reference

Complete catalogue of agentic AI patterns across three orthogonal layers. Production systems compose across all three.

## Table of Contents

1. [Layer 1: Topology Patterns](#layer-1-topology-patterns)
2. [Layer 2: Behavioral Patterns](#layer-2-behavioral-patterns)
3. [Layer 3: Data Flow Patterns](#layer-3-data-flow-patterns)
4. [Pattern Composition Rules](#pattern-composition-rules)
5. [Pattern Selection Decision Framework](#pattern-selection-decision-framework)
6. [Failure Mode Catalogue](#failure-mode-catalogue)

---

## Layer 1: Topology Patterns

How agents are wired and coordinated.

### 1.1 Parallel

Multiple agents run simultaneously and independently. Orchestrator fans out, collects results.

**When to use:** Subtasks are independent, latency is constrained, multi-source research.
**When NOT to use:** Subtasks depend on each other, cost is tightly constrained.
**Latency:** max(worker_1, worker_2, ..., worker_n) -- not the sum.
**Trap:** Uncontrolled fan-out creates runaway cost and rate limit hits. Always cap concurrency.

LangGraph: Use `Send()` API for dynamic fan-out. Use `Annotated[list, operator.add]` reducer for result accumulation.

```python
from langgraph.types import Send

def dispatch(state):
    return [Send("worker", {"task": t}) for t in state["tasks"]]

builder.add_conditional_edges(START, dispatch, ["worker"])
```

### 1.2 Sequential

Agents execute one after another. Output of each feeds into the next. Linear, deterministic, easy to debug.

**When to use:** Strict data dependencies between steps, reliability > speed, pipeline-shaped workflows.
**When NOT to use:** Steps are independent (use Parallel), long chains without validation gates.
**Key risk:** Compound errors. Bad output in step 1 cascades. Add validation gates between high-stakes steps.

LangGraph: Static edges between nodes.

```python
builder.add_edge(START, "planner")
builder.add_edge("planner", "executor")
builder.add_edge("executor", "formatter")
builder.add_edge("formatter", END)
```

### 1.3 Loop

An agent (or group) re-executes until a quality condition is met or a max iteration count is reached. This is the engine behind all self-improving patterns.

**When to use:** Output quality varies and can be evaluated, iterative refinement improves results, tasks need self-correction.
**When NOT to use:** No evaluable quality signal exists, task is deterministic (loop adds only cost).
**CRITICAL:** Always include a max iteration cap. Unbounded loops are a production kill-switch.
**Cost math:** cost = base_cost × avg_iterations. If avg is 3 and base is $0.05, actual is $0.15.

LangGraph: Conditional edge that routes back to the same node or forward to END.

```python
def quality_check(state) -> str:
    if state["score"] >= 0.8 or state["iteration"] >= 3:
        return END
    return "refine"

builder.add_conditional_edges("evaluate", quality_check, {"refine": "generate", END: END})
```

### 1.4 Router

A classifier agent examines the input and dispatches to the appropriate specialist. Only one specialist runs per input.

**When to use:** Requests fall into distinct categories with different handling requirements, intent classification.
**When NOT to use:** Categories overlap heavily (router will oscillate), single handler covers all cases.
**Key design:** Router prompt is the most critical component. Use structured output for routing decisions, not free text. For complete classifier schema design, prompt engineering, confidence thresholding, and implementation patterns, see `structured-classification.md`.
**Scaling:** Max ~15 classes per router. Beyond that, use hierarchical classification (two-stage routing). See `structured-classification.md` §Multi-Intent and Hierarchical Classification.

LangGraph: Conditional edge from router node to specialist nodes.

```python
def route(state) -> str:
    intent = state["classified_intent"]
    return {"billing": "billing_agent", "technical": "tech_agent", "general": "faq_agent"}[intent]

builder.add_conditional_edges("router", route, {"billing_agent": "billing_agent", "tech_agent": "tech_agent", "faq_agent": "faq_agent"})
```

### 1.5 Aggregator

Collects outputs from multiple sources and synthesizes into a unified result. Often paired with Parallel.

**When to use:** Multiple independent analyses need combining, consensus or majority-vote needed, multi-perspective synthesis.
**When NOT to use:** Single source provides sufficient answer, real-time latency constraints make fan-out impractical.
**Mechanism:** Fan-out -> independent processing -> fan-in -> synthesis node.

```python
def synthesize(state):
    analyses = "\n---\n".join(state["results"])  # collected via Annotated[list, operator.add]
    return {"summary": model.invoke(f"Synthesize these independent analyses:\n{analyses}").content}

builder.add_conditional_edges(START, lambda s: [Send("analyst", {"task": t}) for t in s["tasks"]], ["analyst"])
builder.add_edge("analyst", "synthesize")
builder.add_edge("synthesize", END)
```

### 1.6 Network

Agents can communicate with any other agent. No fixed hierarchy -- peer-to-peer wiring where each agent can reach any other.

**When to use:** Peer-to-peer collaboration, dynamic delegation, customer service with specialist routing.
**When NOT to use:** Tasks have a clear predetermined path (use Sequential or Router).
**Risk:** Infinite handoff loops. Always track handoff count and cap it.
**Relationship to Swarm (3.4):** Network is the *topology* (who can talk to whom). Swarm (3.4) is the *data flow mechanism* (how control transfers via handoffs). A swarm runs on a network topology.

LangGraph: Use `create_handoff_tool` + `create_swarm`.

```python
from langgraph_swarm import create_handoff_tool, create_swarm

agent_a = create_agent(model, tools=[
    create_handoff_tool(agent_name="B", description="Hand off for X")
], name="A")

swarm = create_swarm([agent_a, agent_b], default_active_agent="A")
```

### 1.7 Hierarchical

Supervisor decomposes goals and delegates to workers. Workers report back. Supervisor synthesizes and may re-delegate.

**When to use:** Complex tasks requiring decomposition, workers with distinct specializations, need for oversight/quality control at the supervisor level.
**When NOT to use:** Task is simple enough for a single agent, overhead of supervisor reasoning exceeds the benefit.
**Architecture:** Supervisor = Plan-and-Execute behavioral pattern. Workers = ReAct or Tool Use.

```python
researcher = create_agent(model="openai:gpt-4o", tools=[web_search], system_prompt="Research specialist.")
coder = create_agent(model="openai:gpt-4o", tools=[run_code], system_prompt="Code specialist.")

supervisor = create_agent(
    model="claude-sonnet-4-6-20250514",
    tools=[
        researcher.as_tool(name="researcher", description="Research any topic"),
        coder.as_tool(name="coder", description="Write and run code"),
    ],
    system_prompt="You are a supervisor. Delegate tasks to specialists.",
)
```

---

## Layer 2: Behavioral Patterns

How an individual agent reasons and acts internally. These are independent of topology.

### 2.1 ReAct (Reason + Act)

The default agent loop. Model reasons about the task, calls a tool, observes the result, reasons again, repeats until done.

**When to use:** General-purpose agents, tool-calling tasks, any situation where interleaved reasoning and action is needed.
**When NOT to use:** Deterministic pipelines with no decision points (use Sequential + Tool Use instead), tasks requiring upfront multi-step planning before any action (use Plan-and-Execute).
**LangGraph:** The basic conditional edge loop between LLM node and ToolNode.
**LangChain:** `create_agent` implements this by default.

```python
# Minimal ReAct with iteration cap
agent = create_agent(model="claude-sonnet-4-6-20250514", tools=[search, calculator])
```

### 2.2 Reflection / Self-Critique

Agent generates output, then evaluates its own output against criteria, then revises. Separate generation and evaluation steps.

**When to use:** Writing, code generation, analysis where quality varies, tasks with clear evaluation criteria.
**When NOT to use:** No objective quality criteria exist (reflection becomes circular), latency-sensitive tasks where double LLM calls are unacceptable, tasks where first-pass output is consistently sufficient.
**Implementation:** Two LLM calls per iteration: generate, then critique. Critique feeds back as input to next generation.
**Key insight:** The critic prompt must be specific. "Is this good?" fails. "Does this meet criteria X, Y, Z?" works.

```python
def generate(state):
    result = model.invoke(f"Write a response. Previous feedback: {state.get('feedback', 'none')}")
    return {"draft": result.content, "iteration": state.get("iteration", 0) + 1}

def critique(state):
    feedback = model.invoke(f"Critique this draft against criteria [X, Y, Z]:\n{state['draft']}")
    score = 1.0 if "PASS" in feedback.content else 0.0
    return {"feedback": feedback.content, "score": score}

builder.add_conditional_edges("critique", lambda s: END if s["score"] >= 0.8 or s["iteration"] >= 3 else "generate")
```

### 2.3 Plan-and-Execute

Agent creates an explicit plan (list of steps), then executes each step, then can replan if reality diverges.

**When to use:** Complex multi-step tasks, tasks requiring upfront decomposition, supervisor agents in hierarchical topologies.
**When NOT to use:** Simple tasks completable in 1-3 tool calls (planning overhead exceeds benefit), highly dynamic environments where plans become stale before execution completes.
**Implementation:** Planner node (structured output: list of steps) -> executor loop -> optional replanner.
**Key risk:** Over-planning. Plans should be coarse-grained. Detailed sub-plans emerge during execution.

```python
from pydantic import BaseModel

class Plan(BaseModel):
    steps: list[str]

def planner(state):
    plan = model.with_structured_output(Plan).invoke(f"Break this into steps: {state['task']}")
    return {"steps": plan.steps, "current_step": 0}

executor_agent = create_agent(model="claude-sonnet-4-6-20250514", tools=[search])

def executor(state):
    step = state["steps"][state["current_step"]]
    result = executor_agent.invoke({"messages": [{"role": "user", "content": step}]})
    return {"results": [result["messages"][-1].content], "current_step": state["current_step"] + 1}

def should_continue(state) -> str:
    return "executor" if state["current_step"] < len(state["steps"]) else END
```

### 2.4 Generator-Critic

Separate generator and critic agents. Generator proposes, critic evaluates, generator revises. Loop topology with two agents.

**When to use:** High-quality content generation, code review workflows, adversarial quality improvement.
**When NOT to use:** Self-critique is sufficient (use Reflection instead — cheaper, single agent), no clear evaluation rubric for the critic, cost constraints prohibit 2x+ LLM calls per iteration.
**Different from Reflection:** Reflection is self-critique (same agent). Generator-Critic uses separate agents/prompts, allowing specialized evaluation.

```python
generator = create_agent(model="openai:gpt-4o", tools=[search], system_prompt="Generate detailed responses.")
critic = create_agent(model="claude-sonnet-4-6-20250514", tools=[], system_prompt="Evaluate against rubric. Reply PASS or FAIL with reasons.")

def gen_node(state):
    result = generator.invoke({"messages": [{"role": "user", "content": state["task"] + "\nFeedback: " + state.get("critique", "")}]})
    return {"draft": result["messages"][-1].content}

def critic_node(state):
    result = critic.invoke({"messages": [{"role": "user", "content": f"Evaluate:\n{state['draft']}"}]})
    critique = result["messages"][-1].content
    return {"critique": critique, "approved": "PASS" in critique}

builder.add_conditional_edges("critic", lambda s: END if s["approved"] else "generator")
```

### 2.5 STORM (Iterative Research)

Multi-phase research pattern: generate queries -> parallel search -> read sources -> synthesize -> identify gaps -> generate new queries -> repeat.

**When to use:** Deep research tasks, multi-source analysis, investigative workflows.
**When NOT to use:** Simple fact-lookup tasks (a single ReAct call suffices), time-constrained queries where iterative search is too slow, tasks with a single authoritative source.
**Composition:** Parallel (topology) + Loop (topology) + ReAct (behavioral) + Map-Reduce (data flow).

```python
def generate_queries(state):
    queries = model.with_structured_output(QueryList).invoke(f"Generate search queries for: {state['topic']}")
    return {"queries": queries.items}

def search_sources(state):
    return [Send("researcher", {"query": q}) for q in state["queries"]]  # parallel fan-out

def identify_gaps(state):
    gaps = model.with_structured_output(QueryList).invoke(f"What's missing from this research?\n{state['synthesis']}")
    return {"queries": gaps.items, "iteration": state["iteration"] + 1}

# Loop: generate_queries → search (parallel) → synthesize → identify_gaps → repeat or END
builder.add_conditional_edges("gaps", lambda s: END if s["iteration"] >= 3 else "search")
```

### 2.6 Human-in-the-Loop (HITL)

Agent pauses execution at defined points and waits for human approval, editing, or override.

**When to use:** High-stakes actions (payments, external communications, database writes, deployments), regulatory requirements, trust-building phase.
**When NOT to use:** Fully automated pipelines where human latency is unacceptable, low-stakes tasks where the cost of occasional errors is less than the cost of human review.
**LangGraph:** `interrupt()` function inside any node. Resume with `Command(resume=value)`.
**LangChain:** `HumanInTheLoopMiddleware` with `interrupt_on=[tool_names]`.

```python
from langgraph.types import interrupt, Command

def payment_node(state):
    approval = interrupt({"action": "send_payment", "amount": state["amount"], "to": state["recipient"]})
    if approval == "approve":
        return {"payment_sent": True}
    return {"payment_sent": False, "reason": approval}

# Resume: graph.invoke(Command(resume="approve"), config)
```

### 2.7 Tool Use

Agent selects and calls tools from its available set. Not a loop pattern per se, but the mechanism by which agents take action.

**When to use:** Agent needs to interact with external systems, retrieve data, or perform side effects.
**When NOT to use:** Task is purely generative with no external data needs, all required information is already in the context window.

**Design principles (from Claude Code production learnings):**
- Minimize the action space. Every tool is a choice evaluated on every turn.
- Shape tools to model capabilities. A tool that helps a weak model constrains a strong one.
- Design for elicitation. Dedicated tools for asking clarifying questions outperform parameter hacks.
- Progressive disclosure. Hide rarely-needed tools behind a "list advanced tools" meta-tool.
- One clear semantic purpose per tool. Multi-purpose tools confuse routing.

---

## Layer 3: Data Flow Patterns

How information is transformed and routed between nodes.

### 3.1 Map-Reduce

Fan out a task across N workers (map), collect results, synthesize (reduce).

**When to use:** Process many items independently then aggregate (document analysis, multi-source research).
**When NOT to use:** Items have sequential dependencies (use Sequential + Prompt Chaining), N is small enough that a single LLM call can handle all items in context.
**LangGraph:** `Send()` for map, reducer on state key for collection, synthesis node for reduce.

### 3.2 Prompt Chaining

Output of one LLM call becomes input context for the next. Each call transforms or enriches the data.

**When to use:** Sequential processing pipelines, data enrichment, multi-stage transformation.
**When NOT to use:** All transformations can fit in a single well-structured prompt, chain length exceeds 5 steps (context bloat becomes dominant cost).
**Key risk:** Context bloat. Each chain step adds to the context window. Compress or summarize between steps.

### 3.3 Controlled Flow

Explicit routing based on state values. The flow is deterministic given the state, but the state itself is determined by LLM reasoning.

**When to use:** When you need predictable execution paths based on LLM classifications or evaluations.
**When NOT to use:** Flow is always the same regardless of input (use static edges), routing decisions are too nuanced for a classification step (use Network/Swarm instead).
**LangGraph:** Conditional edges with routing functions.

### 3.4 Swarm

The data flow mechanism where agents dynamically hand off control to each other. Each agent decides the next agent and transfers conversational context via the handoff.

**When to use:** Customer service routing, collaborative problem-solving, situations where the right specialist emerges during execution.
**When NOT to use:** Clear predetermined routing exists (use Router + Controlled Flow), small number of agents where a supervisor is simpler, need strict execution ordering.
**Relationship to Network (1.6):** Network (1.6) is the *topology* (peer-to-peer wiring). Swarm is the *data flow pattern* (control transfer via handoffs). A swarm requires a network topology but adds the handoff protocol that moves context between agents.
**LangGraph:** `create_handoff_tool` + `create_swarm` from `langgraph_swarm`.

### 3.5 Subgraph / Reusable Pipeline

Encapsulate a multi-node workflow as a single node in a parent graph. Context isolation between parent and child.

**When to use:** Reusable processing logic shared across multiple parent graphs, context isolation needed, modular architecture.
**When NOT to use:** Logic is used only once (inline nodes are simpler), parent and child need tight state coupling (subgraph isolation gets in the way).
**LangGraph:** Compile a sub-graph and add it as a node in the parent graph.

```python
sub_builder = StateGraph(SubState)
# ... add sub-nodes and edges ...
sub_graph = sub_builder.compile()

parent_builder = StateGraph(ParentState)
parent_builder.add_node("sub_workflow", sub_graph)
```

---

## Pattern Composition Rules

Production systems always compose multiple patterns. Rules for safe composition:

1. **One topology as the skeleton.** Pick the primary topology. Others can be nested (e.g., Sequential overall with Parallel at one step).
2. **Behavioral patterns are per-agent.** The supervisor can be Plan-and-Execute while workers are ReAct.
3. **Data flow patterns are per-edge.** Different edges in the same graph can use different data flow patterns.
4. **HITL is an overlay.** It attaches to any topology at specific nodes. It is not a topology itself.
5. **Loop nests inside anything.** A Loop around a single node for quality control is universal.
6. **Avoid nesting more than 2 topology levels deep.** Hierarchical with nested Parallel workers is fine. Hierarchical with nested Hierarchical supervisors with nested Parallel workers is debugging hell.

### Common Compositions

| System | Topology | Behavioral | Data Flow |
|---|---|---|---|
| Customer support bot | Router | ReAct per specialist + HITL for refunds | Controlled Flow |
| Research assistant | Loop(Parallel) | STORM | Map-Reduce |
| Code review pipeline | Sequential | Generator-Critic at review step | Prompt Chaining |
| Enterprise document processing | Router + Sequential per type | Tool Use + HITL for risk flags | Subgraph per doc type |
| Financial analysis | Hierarchical | Plan-and-Execute (supervisor) + ReAct (workers) | Map-Reduce for data collection |

---

## Composition Escalation Rule

Start simple and escalate only when a specific, measured failure demands it:

```
1. Single agent with tools (ReAct)           <- try this first
2. Sequential pipeline                       <- add when steps have strict ordering
3. Sequential + Loop (quality gates)         <- add when quality requires iteration
4. Router + Sequential                       <- add when inputs vary widely
5. Parallel + Aggregator                     <- add when independent tasks exist
6. Hierarchical                              <- add when scale requires delegation
7. Hierarchical + Swarm or Network           <- only when evidence demands it
```

> **Design axiom: Tiered escalation.** Each level adds coordination overhead. A Hierarchical + Swarm system that could have been a Sequential pipeline wastes tokens on supervision. Measure the failure that motivates the upgrade.

For scenario-specific compositions with state shapes, guardrails, and failure modes, see `scaffolding.md`.

## Pattern Selection Decision Framework

```
START
  │
  ├─ Is the task a single LLM call with tools? ──YES──> ReAct (no topology needed)
  │                                                       Use: create_agent
  │
  ├─ Are there distinct sequential steps? ──YES──> Sequential
  │   └─ Do any steps need quality iteration? ──YES──> Sequential + Loop at that step
  │
  ├─ Are subtasks independent? ──YES──> Parallel
  │   └─ Need synthesis after? ──YES──> Parallel + Aggregator (Map-Reduce)
  │
  ├─ Does input type determine handling? ──YES──> Router
  │
  ├─ Do multiple specialists need to collaborate? ──YES──>
  │   ├─ Clear hierarchy? ──YES──> Hierarchical
  │   └─ Peer-to-peer? ──YES──> Network/Swarm
  │
  ├─ Is iterative research needed? ──YES──> STORM (Loop + Parallel + Map-Reduce)
  │
  └─ Need human approval at specific points? ──YES──> Add HITL overlay to chosen topology
```

---

## Failure Mode Catalogue

> **Design axiom: Document failure modes.** Every topology, behavioral, and data flow pattern has known failure modes. These are not edge cases -- they are expected production behaviors. The same principle applies to evaluation anti-patterns (`evals.md`), LLM-as-judge biases (`llm-as-judge.md`), and production failure modes (`production.md`). Catalog and mitigate before deployment.

| Failure Mode | Pattern Affected | Cause | Mitigation |
|---|---|---|---|
| Infinite loop | Loop, Network | No termination condition or unreachable quality threshold | Max iteration cap, monotonically decreasing retry budget |
| Cascade error | Sequential | Bad output in step N corrupts steps N+1...end | Validation gates between steps |
| Runaway fan-out | Parallel | Unbounded N in dynamic fan-out | Semaphore, batch size limit |
| Router oscillation | Router | Overlapping categories, ambiguous input | Clearer category definitions, fallback category |
| Context explosion | Any long-running | Tool outputs, conversation history grow unbounded | SummarizationMiddleware, context window budget |
| Handoff ping-pong | Network/Swarm | Two agents hand off to each other repeatedly | Handoff counter, max handoff limit |
| Supervisor bottleneck | Hierarchical | Supervisor makes too many LLM calls for coordination | Coarse-grained delegation, async workers |
| Stale state | Any with persistence | Checkpoint from old session has outdated context | TTL on checkpoints, state validation on resume |
| Tool selection thrash | ReAct with many tools | Model can't choose among 20+ tools | Reduce tool count, progressive disclosure, LLMToolSelectorMiddleware |

### Memory Coordination in Multi-Agent Systems

When multiple agents share a task, working memory gains a coordination dimension. Choose the right memory isolation pattern:

| Pattern | Description | When to Use | Risk |
|---|---|---|---|
| **Shared working memory** | Common buffer accessible to all agents (shared scratchpad, blackboard, message bus) | Agents need real-time awareness of each other's progress; collaborative problem-solving | Cross-contamination — one agent's stale or incorrect state pollutes others |
| **Isolated working memory** | Per-agent buffers with controlled inter-agent write access | Agents have distinct responsibilities; outputs combined only at aggregation | Coordination overhead — agents may duplicate work or operate on inconsistent views |
| **Hierarchical working memory** | Supervisor maintains high-level task state; sub-agents maintain local execution state; outputs propagate upward on completion | Hierarchical topology (1.7); supervisor needs oversight without context explosion from sub-agent details | Supervisor bottleneck if sub-agents surface too much state; information loss if too little |

**Implementation guidance:**

- **Shared:** Use a shared state key with a reducer (e.g., `Annotated[list, operator.add]`). Scope writes — agents should append to shared state, not overwrite.
- **Isolated:** Use subgraphs (3.5) for context isolation. Parent graph aggregates results without inheriting sub-agent working memory.
- **Hierarchical:** Supervisor state holds plan-level keys. Sub-agents return structured summaries, not raw reasoning traces. Use `agent.as_tool()` to encapsulate sub-agent output.

**Key failure mode:** Memory cross-contamination in shared buffers. Always key shared memory by agent ID or namespace. Monitor shared state size — unbounded shared buffers cause the same context rot as unbounded conversation history.
