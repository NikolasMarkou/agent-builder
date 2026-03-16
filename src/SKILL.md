---
name: agent-builder
description: Build AI agents from requirements. Covers single-agent, multi-agent, RAG, and production systems. Handles framework selection, pattern selection (topology, behavioral, data flow), state design, tool design, and full implementation. Defaults to Python with LangChain/LangGraph. Supports all major frameworks (CrewAI, Strands, OpenAI Agents SDK, Google ADK, Mastra, etc.). Use this skill whenever the user asks to build an agent, create an agentic system, implement a multi-agent workflow, design agent architecture, scaffold an agent project, or asks "how should I build an agent for X". Also trigger when the user mentions agent patterns, agent topology, ReAct loops, plan-and-execute, supervisor agents, swarm agents, handoffs, agent orchestration, or any agentic design question. Even if the user just says "build me an agent that does X" without mentioning frameworks, use this skill.
---

# Agent Builder

Build production-grade AI agents from requirements. Default stack: Python + LangChain v1.2.x + LangGraph v1.0.x.

## Workflow

Follow these steps in order. Do not skip the assessment phase.

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
| Intent classification + routing | Router | ReAct per specialist | Controlled Flow |
| Quality-gated generation | Loop | Generator-Critic | Controlled Flow |
| Team of specialists | Hierarchical | Plan-and-Execute (supervisor) + ReAct (workers) | Subgraph |
| Flexible peer-to-peer collaboration | Network | ReAct + Handoffs | Swarm |
| High-stakes with human approval | Any + HITL gates | Any + HITL | Any |

### Step 3: Select Framework

Default is **LangChain/LangGraph (Python)**. Read `references/langchain-langgraph.md` for implementation patterns.

Override the default only when:

| Condition | Use Instead | Read |
|---|---|---|
| AWS-native deployment, model-driven approach | Strands Agents | `references/frameworks.md` |
| Role-based team, rapid prototyping | CrewAI | `references/frameworks.md` |
| OpenAI-only stack, voice/realtime | OpenAI Agents SDK | `references/frameworks.md` |
| Azure/.NET/Java enterprise | Semantic Kernel / MS Agent Framework | `references/frameworks.md` |
| Google Cloud native | Google ADK | `references/frameworks.md` |
| TypeScript/JS application | Mastra | `references/frameworks.md` |
| RAG-heavy, document processing | LlamaIndex | `references/frameworks.md` |
| Prompt optimization | DSPy | `references/frameworks.md` |
| Model-agnostic, persistent memory | Agno | `references/frameworks.md` |
| Lightweight, open-model focus | Smolagents | `references/frameworks.md` |

### Step 4: Build

Read the appropriate reference file for your selected framework, then implement.

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

Read `references/production.md` before deploying. Covers:
- Context engineering (context rot, token budget, three-artefact architecture)
- Tool design principles (minimize action space, shape to model capabilities, elicitation)
- Evaluation strategy (domain-specific evals, not generic benchmarks). Read `references/evals.md` for comprehensive evaluation guidance: frameworks, benchmarks, metrics, LLM-as-judge, safety evals, monitoring, and building eval pipelines.
- Cost modeling (token math at scale)
- Observability (LangSmith tracing, structured logging)
- Guardrails (input validation, output validation, tool permission scoping)
- Failure modes catalogue and mitigation

---

## Code Templates

### Template 1: Simple Agent (create_agent)

```python
from langchain.agents import create_agent
from langchain.tools import tool

@tool
def search(query: str) -> str:
    """Search the web for information."""
    # Implementation here
    return f"Results for: {query}"

agent = create_agent(
    model="claude-sonnet-4-5-20250929",  # or "openai:gpt-4.1", "google_genai:gemini-2.5-flash"
    tools=[search],
    system_prompt="You are a helpful assistant.",
)

result = agent.invoke({"messages": [{"role": "user", "content": "Find X"}]})
```

### Template 2: ReAct Agent with Persistence (LangGraph)

```python
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.prebuilt import ToolNode
from langgraph.checkpoint.memory import InMemorySaver
from langchain_anthropic import ChatAnthropic
from langchain_core.tools import tool

@tool
def get_data(query: str) -> str:
    """Fetch data from the database."""
    return "data result"

llm = ChatAnthropic(model="claude-sonnet-4-5-20250929").bind_tools([get_data])

def call_llm(state: MessagesState) -> dict:
    return {"messages": [llm.invoke(state["messages"])]}

def should_call_tools(state: MessagesState) -> str:
    if state["messages"][-1].tool_calls:
        return "tools"
    return END

builder = StateGraph(MessagesState)
builder.add_node("llm", call_llm)
builder.add_node("tools", ToolNode([get_data]))
builder.add_edge(START, "llm")
builder.add_conditional_edges("llm", should_call_tools)
builder.add_edge("tools", "llm")

graph = builder.compile(checkpointer=InMemorySaver())
result = graph.invoke(
    {"messages": [{"role": "user", "content": "Get the latest data"}]},
    {"configurable": {"thread_id": "session-1"}},
)
```

### Template 3: Multi-Agent Supervisor (LangGraph Swarm)

```python
from langchain.agents import create_agent
from langgraph_swarm import create_handoff_tool, create_swarm
from langgraph.checkpoint.memory import InMemorySaver

researcher = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[search_tool, create_handoff_tool(agent_name="Writer", description="Hand off when research is complete")],
    name="Researcher",
    system_prompt="You research topics thoroughly, then hand off to the Writer.",
)

writer = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[create_handoff_tool(agent_name="Researcher", description="Get more research if needed")],
    name="Writer",
    system_prompt="You write reports based on research provided.",
)

swarm = create_swarm([researcher, writer], default_active_agent="Researcher")
app = swarm.compile(checkpointer=InMemorySaver())

result = app.invoke(
    {"messages": [{"role": "user", "content": "Write a report on X"}]},
    {"configurable": {"thread_id": "report-1"}},
)
```

### Template 4: Parallel Fan-Out/Fan-In (LangGraph)

```python
from langgraph.types import Send
from langgraph.graph import StateGraph, START, END
from typing import TypedDict, Annotated
import operator

class State(TypedDict):
    tasks: list[str]
    results: Annotated[list[dict], operator.add]
    final_output: str

def dispatch(state: State):
    return [Send("worker", {"task": t, "context": ""}) for t in state["tasks"]]

def worker(state: dict) -> dict:
    result = llm.invoke(f"Complete: {state['task']}")
    return {"results": [{"task": state["task"], "output": result.content}]}

def synthesize(state: State) -> dict:
    combined = "\n".join(f"{r['task']}: {r['output']}" for r in state["results"])
    return {"final_output": llm.invoke(f"Synthesize:\n{combined}").content}

builder = StateGraph(State)
builder.add_node("worker", worker)
builder.add_node("synthesize", synthesize)
builder.add_conditional_edges(START, dispatch, ["worker"])
builder.add_edge("worker", "synthesize")
builder.add_edge("synthesize", END)
```

### Template 5: Human-in-the-Loop with Interrupt

```python
from langgraph.types import interrupt, Command

def agent_with_approval(state: MessagesState) -> dict:
    response = llm.invoke(state["messages"])
    if response.tool_calls:
        approval = interrupt({
            "message": "Approve this action?",
            "tool": response.tool_calls[0],
        })
        if approval != "yes":
            return {"messages": [{"role": "assistant", "content": "Cancelled."}]}
    return {"messages": [response]}

# Resume after human approval:
# graph.invoke(Command(resume="yes"), config)
```

---

## Key Packages (March 2026)

```bash
pip install langchain "langchain[anthropic]"  # or [openai], [google-genai]
pip install langgraph
pip install deepagents                         # batteries-included layer
pip install langchain-mcp-adapters             # MCP integration
```

| Package | Version | Purpose |
|---|---|---|
| `langchain` | 1.2.x | Core: models, tools, agents, middleware |
| `langgraph` | 1.0.x | Orchestration: state machines, durable execution |
| `deepagents` | 0.4.x | Batteries-included: filesystem, subagents, planning |
| `langchain-mcp-adapters` | 0.2.0 | MCP tool integration |

---

## Reference Files

Read these as needed. Do NOT load all of them upfront.

| File | When to Read |
|---|---|
| `references/patterns.md` | When selecting topology, behavioral, or data flow patterns. Contains full pattern catalogue with decision criteria, implementation details, and composition rules. |
| `references/langchain-langgraph.md` | When building with the default stack. Contains LangGraph state management, edges, streaming, memory, middleware, MCP integration, and Deep Agents. |
| `references/frameworks.md` | When the user explicitly requests a non-default framework, or when the task clearly maps to a specialized framework. Contains per-framework implementation guidance. |
| `references/production.md` | Before any production deployment. Contains context engineering, tool design, evaluation, cost modeling, observability, guardrails, and failure modes. |
| `references/evals.md` | When designing evaluation strategy for agents. Contains evaluation frameworks, benchmarks, metrics, LLM-as-judge, human evaluation, safety evaluation, production monitoring, eval pipeline architecture, and anti-patterns. |
