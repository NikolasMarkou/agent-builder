# LangChain + LangGraph Implementation Reference

Default stack for agent-builder. Based on LangChain v1.2.x, LangGraph v1.0.x, Deep Agents v0.4.x (March 2026).

## Table of Contents

1. [Stack Architecture](#stack-architecture)
2. [LangChain Core](#langchain-core)
3. [LangGraph Core](#langgraph-core)
4. [State Management](#state-management)
5. [Edges and Control Flow](#edges-and-control-flow)
6. [Persistence and Checkpointing](#persistence-and-checkpointing)
7. [Human-in-the-Loop](#human-in-the-loop)
8. [Streaming](#streaming)
9. [Memory](#memory)
10. [Middleware](#middleware)
11. [MCP Integration](#mcp-integration)
12. [Multi-Agent Patterns](#multi-agent-patterns)
13. [Deep Agents](#deep-agents)
14. [API Quick Reference](#api-quick-reference)

---

## Stack Architecture

| Layer | Package | Role |
|---|---|---|
| **LangChain** | `langchain` v1.2.x | Core: models, tools, agents, middleware, structured output |
| **LangGraph** | `langgraph` v1.0.x | Orchestration: state machines, durable execution, checkpointing, streaming |
| **Deep Agents** | `deepagents` v0.4.x | Batteries-included: task planning, virtual filesystem, subagents, long-term memory |

The old chain-based paradigm (LCEL pipes, `SequentialChain`) is in `langchain-legacy`. Current paradigm: `create_agent`, middleware, LangGraph `StateGraph`.

```bash
pip install langchain "langchain[anthropic]"  # or [openai], [google-genai]
pip install langgraph
pip install deepagents
```

---

## LangChain Core

### create_agent

Single entry point for simple-to-moderate agents. Built on LangGraph under the hood.

```python
from langchain.agents import create_agent
from langchain.tools import tool

@tool
def search(query: str) -> str:
    """Search the web for information."""
    return f"Results for: {query}"

agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[search],
    system_prompt="You are a helpful assistant.",
)

result = agent.invoke({"messages": [{"role": "user", "content": "Find X"}]})
```

Parameters:
- `model`: `str` (`"openai:gpt-4o"`, `"claude-sonnet-4-5-20250929"`) or `BaseChatModel` instance
- `tools`: list of `@tool` functions, `BaseTool` instances, or MCP tools
- `system_prompt`: `str` or `SystemMessage`
- `response_format`: type for structured output
- `middleware`: list of middleware

### init_chat_model

Provider-agnostic model initialization.

```python
from langchain.chat_models import init_chat_model

model = init_chat_model("openai:gpt-4o", temperature=0)
model = init_chat_model("claude-sonnet-4-5-20250929", temperature=0.5)
model = init_chat_model("google_genai:gemini-2.5-flash-lite")
model = init_chat_model("ollama:llama3")
```

### Tools

Decorated Python functions. Docstring = tool description. Type hints = schema.

```python
from langchain.tools import tool, ToolRuntime
from dataclasses import dataclass

@dataclass
class UserContext:
    user_id: str

@tool
def get_account(runtime: ToolRuntime[UserContext]) -> str:
    """Get current user's account info."""
    user_id = runtime.context.user_id
    return f"Account for {user_id}"
```

`ToolRuntime` provides: `runtime.context` (immutable config), `runtime.state` (agent state), `runtime.store` (long-term memory), `runtime.config` (LangGraph config). Hidden from model schema.

### Structured Output

```python
from dataclasses import dataclass

@dataclass
class Analysis:
    sentiment: str
    confidence: float
    summary: str

agent = create_agent(model="claude-sonnet-4-5-20250929", tools=[...], response_format=Analysis)
result = agent.invoke({"messages": [...]})
structured = result["structured_response"]  # Analysis instance

# Or on model directly:
structured_llm = model.with_structured_output(Analysis)
```

Auto strategy (default) picks best approach from model profile. ProviderStrategy for native structured output. ToolStrategy for any model with tool calling.

### Standard Content Blocks

Normalize provider-specific responses:

```python
response = model.invoke("question")
for block in response.content_blocks:
    if block["type"] == "reasoning": ...
    elif block["type"] == "text": ...
    elif block["type"] == "web_search_call": ...
```

---

## LangGraph Core

LangGraph models workflows as directed graphs: State + Nodes + Edges.

- **State**: typed dict or Pydantic model flowing through all nodes
- **Nodes**: functions that take state, return partial state updates
- **Edges**: static (always go to next) or conditional (route based on state)

```python
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.prebuilt import ToolNode
from langchain.chat_models import init_chat_model

model = init_chat_model("claude-sonnet-4-5-20250929")
tools = [search]  # your @tool-decorated functions
tool_node = ToolNode(tools)

def agent_node(state: MessagesState):
    return {"messages": [model.bind_tools(tools).invoke(state["messages"])]}

def route(state: MessagesState) -> str:
    if state["messages"][-1].tool_calls:
        return "tools"
    return END

builder = StateGraph(MessagesState)
builder.add_node("agent", agent_node)
builder.add_node("tools", tool_node)
builder.add_edge(START, "agent")
builder.add_conditional_edges("agent", route, {"tools": "tools", END: END})
builder.add_edge("tools", "agent")  # cycle

graph = builder.compile()
```

---

## State Management

### TypedDict State

```python
from typing import TypedDict, Annotated
from langgraph.graph.message import add_messages

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]  # reducer: append
    plan: str
    iterations: int
    error: str | None
```

### Pydantic State

```python
from pydantic import BaseModel

class ResearchState(BaseModel):
    query: str
    search_results: list[str] = []
    draft: str = ""
    approved: bool = False
```

### MessagesState (built-in)

```python
from langgraph.graph import MessagesState
# Equivalent to: class State(TypedDict): messages: Annotated[list, add_messages]
```

### Reducers

Control how node outputs merge into state. Without reducer: overwrite. With reducer: function applied.

```python
# Custom: keep last N messages
def keep_last_10(existing, update):
    return (existing + update)[-10:]

class State(TypedDict):
    messages: Annotated[list, keep_last_10]

# Accumulation: use operator.add
import operator
class State(TypedDict):
    results: Annotated[list[dict], operator.add]
```

---

## Edges and Control Flow

### Static Edges

```python
builder.add_edge(START, "planner")
builder.add_edge("planner", "executor")
```

### Conditional Edges

```python
def should_continue(state: MessagesState) -> str:
    if state["messages"][-1].tool_calls:
        return "tools"
    return END

builder.add_conditional_edges("llm", should_continue)
```

### Parallel Fan-Out with Send

```python
from langgraph.types import Send

def distribute(state):
    return [Send("worker", {"task": t}) for t in state["tasks"]]

builder.add_conditional_edges("coordinator", distribute, ["worker"])
```

### Dynamic Routing from Inside a Node (Command)

```python
from langgraph.types import Command

def smart_node(state):
    if state["needs_review"]:
        return Command(update={"status": "reviewing"}, goto="reviewer")
    return Command(update={"status": "done"}, goto=END)
```

---

## Persistence and Checkpointing

### Development

```python
from langgraph.checkpoint.memory import InMemorySaver

graph = builder.compile(checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "user-1"}}
graph.invoke(input, config)
```

### Production

```python
from langgraph.checkpoint.postgres import PostgresSaver

checkpointer = PostgresSaver.from_conn_string("postgresql://...")
graph = builder.compile(checkpointer=checkpointer)
```

Also: `SqliteSaver` for single-process.

### State Inspection

```python
state = graph.get_state(config)          # current state
history = graph.get_state_history(config) # all checkpoints
graph.update_state(config, {"key": "new_value"})  # modify externally
```

---

## Human-in-the-Loop

```python
from langgraph.types import interrupt, Command

def node_with_approval(state):
    decision = interrupt({
        "message": "Approve this action?",
        "actions": state["planned_actions"],
    })
    if decision == "approve":
        return {"approved": True}
    elif decision == "reject":
        return {"approved": False, "cancelled": True}
    else:
        return {"approved_actions": decision}  # modified list

# Resume:
graph.invoke(Command(resume="approve"), config)
```

---

## Streaming

```python
# Token-level streaming
async for event in graph.astream_events(input, config, version="v2"):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="")

# Node-level streaming
for chunk in graph.stream(input, config, stream_mode="updates"):
    node_name = list(chunk.keys())[0]
    print(f"{node_name}: {chunk[node_name]}")
```

Stream modes: `"values"` (full state after each step), `"updates"` (partial updates per node), `"messages"` (LLM token chunks).

---

## Memory

### Short-term (Conversation)

Automatic via `messages` state key with `add_messages` reducer + checkpointer.

### Long-term (Cross-session)

Via LangGraph Memory Store:

```python
from langgraph.store.memory import InMemoryStore  # dev
from langgraph.store.postgres import PostgresStore  # prod

store = InMemoryStore()

@tool
def save_preference(key: str, value: str, runtime: ToolRuntime) -> str:
    """Save a user preference."""
    runtime.store.put(("preferences",), key, {"value": value})
    return "Saved."

agent = create_agent(model="openai:gpt-4o", tools=[save_preference], store=store)
```

### Summarization

```python
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[...],
    middleware=[SummarizationMiddleware()],
)
```

Auto-triggers on `ContextOverflowError`.

---

## Middleware

### Prebuilt

| Middleware | Purpose |
|---|---|
| `SummarizationMiddleware` | Compress history on context overflow |
| `HumanInTheLoopMiddleware` | Pause for human approval |
| `ModelRetryMiddleware` | Exponential backoff on model failures |
| `ModelFallbackMiddleware` | Fallback to alternate models |
| `ContentModerationMiddleware` | OpenAI moderation on I/O |
| `PIIDetectionMiddleware` | Detect and redact PII |
| `LLMToolSelectorMiddleware` | Filter tools per query |
| `ToolRetryMiddleware` | Retry failed tool calls |
| `ContextEditingMiddleware` | Edit message history before model calls |
| `TodoListMiddleware` | `write_todos` for task decomposition |
| `SubAgentMiddleware` | Spawn subagents |
| `AnthropicPromptCachingMiddleware` | Reduce redundant token processing |
| `FilesystemMiddleware` | Virtual filesystem tools |

### Custom Middleware

```python
from langchain.agents import create_middleware

@create_middleware
async def log_calls(request, handler):
    print(f"Calling with {len(request.messages)} messages")
    response = await handler(request)
    return response

# Class-based for full control:
from langchain.agents.middleware import AgentMiddleware

class Custom(AgentMiddleware):
    def before_model(self, state, runtime): ...
    def wrap_model_call(self, request, handler): ...
    def wrap_tool_call(self, request, handler): ...
```

### Common Patterns

**Dynamic model routing:**
```python
@create_middleware
async def route_model(request, handler):
    last_msg = request.messages[-1].content if request.messages else ""
    if len(last_msg) < 200 and not any(kw in last_msg for kw in ["analyze", "compare", "plan"]):
        request.model = init_chat_model("openai:gpt-4o-mini")
    return await handler(request)
```

**Model fallback:**
```python
middleware=[ModelFallbackMiddleware(fallbacks=["claude-sonnet-4-5-20250929", "openai:gpt-4o-mini"])]
```

**Tool filtering:**
```python
middleware=[LLMToolSelectorMiddleware(model="openai:gpt-4o-mini", max_tools=3, always_include=["search"])]
```

---

## MCP Integration

```python
from langchain_mcp_adapters.client import MultiServerMCPClient

client = MultiServerMCPClient({
    "filesystem": {
        "transport": "stdio",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
    },
    "github": {
        "transport": "streamable_http",
        "url": "https://my-github-mcp-server/mcp",
        "headers": {"Authorization": "Bearer ..."},
    },
})

tools = await client.get_tools()
agent = create_agent(model="claude-sonnet-4-5-20250929", tools=tools)
```

Features: multimodal tool content, tool interceptors for runtime context, resources/prompts loading, elicitation, progress notifications.

---

## Multi-Agent Patterns

### Subagents (parent delegates to children)

```python
research_agent = create_agent(model="openai:gpt-4o", tools=[web_search], system_prompt="Research specialist.")

main_agent = create_agent(
    model="openai:gpt-4o",
    tools=[research_agent.as_tool(name="researcher", description="Research any topic")],
)
```

### Handoffs (Swarm)

```python
from langgraph_swarm import create_handoff_tool, create_swarm

agent_a = create_agent(model, tools=[
    tool_1,
    create_handoff_tool(agent_name="B", description="Hand off for Y"),
], name="A", system_prompt="...")

swarm = create_swarm([agent_a, agent_b], default_active_agent="A")
app = swarm.compile(checkpointer=InMemorySaver())
```

### Custom LangGraph Multi-Agent (full control)

Build a `StateGraph` where each node is an agent call. Use conditional edges for routing between agents. Use `Send()` for parallel agent execution.

```python
from langgraph.graph import StateGraph, MessagesState, START, END

planner = create_agent(model="openai:gpt-4o", tools=[], system_prompt="Break tasks into steps.")
researcher = create_agent(model="openai:gpt-4o", tools=[web_search], system_prompt="Research specialist.")
writer = create_agent(model="openai:gpt-4o", tools=[], system_prompt="Write final output from research.")

def plan_node(state: MessagesState):
    return {"messages": [planner.invoke(state["messages"])]}

def research_node(state: MessagesState):
    return {"messages": [researcher.invoke(state["messages"])]}

def write_node(state: MessagesState):
    return {"messages": [writer.invoke(state["messages"])]}

def route_after_plan(state: MessagesState) -> str:
    last = state["messages"][-1].content
    return "researcher" if "RESEARCH:" in last else "writer"

builder = StateGraph(MessagesState)
builder.add_node("planner", plan_node)
builder.add_node("researcher", research_node)
builder.add_node("writer", write_node)
builder.add_edge(START, "planner")
builder.add_conditional_edges("planner", route_after_plan)
builder.add_edge("researcher", "writer")
builder.add_edge("writer", END)

graph = builder.compile(checkpointer=InMemorySaver())
```

---

## Deep Agents

Batteries-included layer. Same ReAct loop with built-in filesystem, task planning, subagent spawning, long-term memory, auto-summarization.

```python
from deepagents import create_deep_agent

agent = create_deep_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[custom_tool],
    system_prompt="You are a coding assistant.",
)
```

Built-in tools: `ls`, `read_file`, `write_file`, `edit_file`, `write_todos`.
Default middleware: SubAgentMiddleware, SummarizationMiddleware, AnthropicPromptCachingMiddleware, PatchToolCallsMiddleware.
Optional: MemoryMiddleware, SkillsMiddleware, HumanInTheLoopMiddleware.

Sandbox backends: in-memory, local disk, LangGraph store, Modal, Daytona, Deno.

### Task Planning and Subagents

Deep Agents decompose complex tasks via `write_todos`, then spawn subagents for each step:

```python
agent = create_deep_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[custom_tool],
    system_prompt="You are a coding assistant.",
    middleware=[
        MemoryMiddleware(store=PostgresStore.from_conn_string("postgresql://...")),
        HumanInTheLoopMiddleware(interrupt_on=["write_file", "edit_file"]),
    ],
    sandbox="local",  # or "modal", "daytona", "deno"
)

# Deep agents auto-manage: task decomposition, file I/O, subagent delegation,
# context summarization, and long-term memory across sessions.
# The agent decides when to spawn subagents based on task complexity.
```

**When to use:** Tasks requiring filesystem access, multi-step planning, or subagent coordination where building a custom `StateGraph` is overkill.
**When NOT to use:** You need fine-grained control over agent routing, custom state schemas, or non-ReAct behavioral patterns.

---

## Failure Modes

See the Failure Mode Catalogue in `patterns.md` for the full list of pattern-level failure modes and mitigations. The most common LangGraph-specific issues:

- **Checkpoint bloat**: Set TTL on checkpoints, use `PostgresSaver` with periodic pruning.
- **Fan-out cost explosion**: Cap `len(tasks)` before `Send()` dispatch, add concurrency limit.

## Cost Guidelines

| Pattern | Cost Profile | Budget Rule |
|---|---|---|
| `create_agent` (simple) | 1-3 LLM calls | Base cost × avg_tool_calls |
| ReAct with persistence | 3-10 LLM calls per turn | Base × avg_iterations. Budget $0.05-0.50/turn with Claude Sonnet |
| Swarm (handoffs) | N agents × avg calls each | Budget per-agent, cap total handoffs |
| Parallel fan-out | N workers × 1 call each + 1 synthesis | Linear in N. Cap N at 10-20 |
| Human-in-the-loop | Same as base pattern + resume overhead | Checkpoint storage cost adds ~$0.001/checkpoint |
| Deep Agents | Highly variable, subagent spawning multiplies | Set `max_budget` if available, monitor via LangSmith |

---

## API Quick Reference

### LangChain

| API | Purpose |
|---|---|
| `create_agent(model, tools, ...)` | Single entry point for agents |
| `init_chat_model(model_string)` | Provider-agnostic model init |
| `@tool` | Decorator to create tools |
| `ToolRuntime` | Access context/state/store in tools |
| `model.with_structured_output(Schema)` | Structured output |
| `create_middleware` | Custom middleware decorator |

### LangGraph

| API | Purpose |
|---|---|
| `StateGraph(State)` | Create graph with state schema |
| `builder.add_node(name, fn)` | Register a node |
| `builder.add_edge(a, b)` | Static edge |
| `builder.add_conditional_edges(a, fn, map)` | Dynamic routing |
| `builder.compile(checkpointer, store)` | Compile to executable |
| `graph.invoke(input, config)` | Sync execution |
| `graph.stream(input, config, stream_mode)` | Streaming |
| `graph.astream_events(input, config)` | Token-level streaming |
| `graph.get_state(config)` | Inspect thread state |
| `graph.update_state(config, values)` | Modify state externally |
| `interrupt(value)` | Pause execution |
| `Command(update, goto)` | Dynamic routing from node |
| `Send(node, state)` | Fan-out to parallel instances |
| `ToolNode(tools)` | Prebuilt tool execution node |
| `MessagesState` | Built-in message state |
| `InMemorySaver()` | Dev checkpointer |
| `PostgresSaver` | Prod checkpointer |
| `InMemoryStore()` | Dev memory store |
| `PostgresStore` | Prod memory store |
