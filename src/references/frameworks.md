# Alternative Frameworks Reference

Use this reference when the default LangChain/LangGraph stack is not the best fit. Each section covers when to choose the framework, architecture, and implementation patterns.

## Table of Contents

1. [Framework Selection Matrix](#framework-selection-matrix)
2. [CrewAI](#crewai)
3. [Strands Agents (AWS)](#strands-agents)
4. [OpenAI Agents SDK](#openai-agents-sdk)
5. [Google ADK](#google-adk)
6. [Semantic Kernel / Microsoft Agent Framework](#semantic-kernel--microsoft-agent-framework)
7. [LlamaIndex](#llamaindex)
8. [Mastra](#mastra)
9. [Agno](#agno)
10. [Smolagents](#smolagents)
11. [DSPy](#dspy)
12. [Head-to-Head Comparisons](#head-to-head)

---

## Framework Selection Matrix

| Use Case | Best Choice | Runner-up |
|---|---|---|
| Simple chatbots | LangChain, OpenAI Agents SDK | Strands |
| Complex multi-agent systems | LangGraph | Strands Graph, CrewAI |
| RAG pipelines | LlamaIndex | Haystack*, LangChain |
| Document processing | LlamaIndex (LlamaParse) | Haystack* |
| Data analysis agents | LangGraph | Strands |
| Code generation agents | OpenAI Agents SDK, Smolagents | Strands |
| Research agents | LangGraph, AutoGen* | Smolagents |
| AWS-native production | Strands Agents | LangGraph |
| Azure/Microsoft production | Microsoft Agent Framework | Semantic Kernel |
| Google Cloud production | Google ADK | LangGraph |
| TypeScript/JS apps | Mastra | Vercel AI SDK* |
| .NET/Java enterprise | Semantic Kernel | Google ADK (Java) |
| Open/local model workflows | Smolagents, Agno | Strands (Ollama) |
| Prompt optimization | DSPy | (unique niche) |
| Persistent agent memory | Letta (MemGPT)* | Agno (learning=True) |
| Voice/realtime agents | OpenAI Agents SDK, Strands BidiAgent | Google ADK |
| Serverless deployment | Strands (Lambda) | LangGraph Platform |
| Rapid prototyping | Strands, Agno, OpenAI SDK | CrewAI |

\* *Not covered in this guide — external documentation only. Haystack: open-source RAG/NLP pipeline framework. AutoGen: Microsoft multi-agent conversation framework. Vercel AI SDK: React/Next.js AI integration library. Letta (MemGPT): persistent-memory agent framework built on virtual context management.*

---

## CrewAI

**Architecture:** Role-based multi-agent. Define agents with roles/goals/backstories, assemble into crews with processes.
**License:** MIT | **Stars:** ~44K | **Language:** Python
**Best for:** Rapid team-of-agents prototyping, sequential/hierarchical role-based workflows.

**Core concepts:**
- **Agent**: role + goal + backstory + tools + LLM
- **Task**: description + expected_output + assigned agent
- **Crew**: collection of agents + tasks + process (sequential, hierarchical, or consensual)
- **Flow**: multi-crew orchestration with state management

**When to choose over LangGraph:**
- Team-based metaphor maps naturally to the problem
- Speed of prototyping matters more than fine-grained control
- Workflow is sequential or hierarchical with clear role assignments

**When NOT to choose:**
- Need explicit cycles, custom state machines, durable checkpointing
- Need fine-grained control over every state transition
- Complex conditional branching beyond sequential/hierarchical

**Memory:** 4 types (short-term, long-term, entity, contextual).
**Enterprise:** CrewAI AMP (managed platform).

---

## Strands Agents

**Architecture:** Model-driven / minimalist. Agent = prompt + tools + model. LLM drives all planning and tool selection.
**License:** Apache 2.0 | **Stars:** ~10K+ | **Language:** Python, TS (preview)
**Best for:** AWS-native deployment, minimal boilerplate, model-driven approach, rapid time-to-production.

**Core concepts:**
- Agent defined with system prompt + tools list — the LLM decides what to do
- Tools via `@tool` decorator (custom), 20+ pre-built tools, or MCP servers (first-class)
- Model-agnostic: Bedrock, Anthropic, OpenAI, Ollama, LiteLLM, + community providers
- Structured output via Pydantic `output_schema`

**When to choose over LangGraph:**
- AWS deployment (Lambda, Fargate, EKS, AgentCore managed runtime)
- Model-driven approach (trust the LLM to plan, no explicit graph needed)
- Minimal framework overhead wanted
- Rapid time-to-production (days vs months per AWS internal experience)
- Need native MCP support (first-class, not via adapters)
- Cross-framework agent interop needed (A2A protocol)

**When NOT to choose:**
- Need explicit state machines with durable checkpointing
- Need fine-grained control over every state transition
- Need built-in HITL interrupt/resume semantics
- Need state machine visualization for debugging complex flows

**Multi-agent (built-in):**
- **Swarm:** Agent-driven handoffs with emergent coordination. Agents decide who handles next.
- **Graph:** Deterministic directed graph with conditional edges. Supports DAG and cyclic topologies.
- **Workflow:** Dependency-based task graph with automatic parallelism for independent branches.
- **Agents as Tools:** Supervisor pattern — wrap specialist agents as `@tool` functions.

**Memory:** Built-in conversational, SessionManager for persistence, community packages for Redis/Valkey.
**Observability:** Native OpenTelemetry — traces, spans, metrics. Compatible with Langfuse, X-Ray, Datadog, Jaeger.
**Production:** AWS AgentCore (managed serverless runtime, up to 8hr tasks), Lambda, Docker/K8s.
**Unique:** A2A protocol for cross-framework agent interop, Agent SOPs for natural language workflows, semantic tool retrieval for 100+ tool sets.

For implementation patterns and deployment guidance, read `references/strands.md`.

---

## OpenAI Agents SDK

**Architecture:** Model-driven / minimalist. Agent = instructions + tools + model.
**License:** MIT | **Stars:** ~19K | **Language:** Python, TS
**Best for:** OpenAI-centric stacks, built-in tracing, voice/realtime agents.

**Core concepts:**
- Agent: name + instructions + tools + model
- Runner: executes agent loop
- Handoffs: transfer control between agents
- Guardrails: input/output validation

**When to choose over LangGraph:**
- All-OpenAI stack
- Need built-in voice/realtime support
- Simple multi-agent with handoffs
- Want minimal framework surface area

**When NOT to choose:**
- Need model agnosticism (OpenAI-centric by design)
- Need durable execution with checkpointing
- Complex state management beyond messages

**Multi-agent:** Handoff tools between agents. Swarm pattern.
**Enterprise:** OpenAI Enterprise platform.

---

## Google ADK

**Architecture:** Multi-agent with hierarchical delegation. Agent = instructions + tools + sub-agents.
**License:** Apache 2.0 | **Stars:** ~10K+ | **Language:** Python, TS, Java
**Best for:** Google Cloud native, multi-language enterprise, Vertex AI integration.

**Core concepts:**
- Agent: name + model + instructions + tools + sub_agents
- Hierarchical delegation: parent delegates to children automatically
- Built-in: Google Search, code execution, RAG via Vertex AI
- Session/memory management via Session Service

**When to choose over LangGraph:**
- Google Cloud deployment (Agentspace, Vertex AI)
- Multi-language need (Python, TS, Java)
- Hierarchical agent delegation is the natural fit

**When NOT to choose:**
- Need explicit state machines with custom graph topologies (ADK is hierarchical-first)
- Non-Google cloud deployment (no managed runtime outside Vertex AI)
- Need fine-grained control over agent communication patterns beyond parent-child delegation

**Key insight from Google's architecture:** Context is a "compiled view over a richer stateful system." This aligns with the context engineering principle of keeping context small and truth central.

```python
from google.adk import Agent

agent = Agent(
    name="researcher",
    model="gemini-2.5-flash",
    instruction="You are a research assistant. Search for information and summarize findings.",
    tools=[google_search],
)
response = await agent.run_async("Find the latest AI agent frameworks")
```

---

## Semantic Kernel / Microsoft Agent Framework

**Architecture:** Orchestration-first with enterprise focus. Plugin-based architecture.
**License:** MIT | **Stars:** ~27K | **Language:** C#, Python, Java
**Best for:** .NET/Java enterprise, Azure-native, SOC 2/HIPAA compliance.

**Note:** Microsoft is merging AutoGen + Semantic Kernel into unified Microsoft Agent Framework. Target this for new Microsoft-ecosystem projects.

**Core concepts:**
- Kernel: central orchestrator
- Plugins: collections of functions (tools)
- Planners: automatic step generation
- Memory: semantic memory with vector stores

**When to choose:** Azure ecosystem, C#/.NET team, Java enterprise, compliance requirements.

**When NOT to choose:**
- Python-only team (LangGraph is more Pythonic and has larger Python community)
- Need lightweight framework (Semantic Kernel has heavy enterprise abstractions)
- Need custom graph-based orchestration (planner abstraction limits topology control)

```csharp
// C# example
using Microsoft.SemanticKernel;

var kernel = Kernel.CreateBuilder()
    .AddAzureOpenAIChatCompletion("gpt-4o", endpoint, apiKey)
    .Build();
kernel.Plugins.AddFromType<SearchPlugin>();

var result = await kernel.InvokePromptAsync("Find information about {{$input}}", new() { ["input"] = "AI agents" });
```

---

## LlamaIndex

**Architecture:** RAG-first, extended into agents.
**License:** MIT | **Stars:** ~46K | **Language:** Python, TS
**Best for:** RAG pipelines, document processing, complex retrieval.

**Core concepts:**
- Index: data structure over documents
- Query Engine: retrieval + synthesis
- Agent: LLM + tools (including query engines as tools)
- LlamaParse: advanced document parsing

**When to choose over LangChain for RAG:**
- Complex document processing (tables, images, PDFs)
- Need advanced retrieval (recursive, hybrid, agentic RAG)
- LlamaParse for difficult document formats

**When NOT to choose:**
- Agent orchestration is the primary need (LlamaIndex agents are secondary to its RAG focus)
- Simple retrieval where LangChain's built-in retriever is sufficient
- Need complex multi-agent topologies (use LangGraph, combine with LlamaIndex for retrieval)

**Can combine with LangGraph:** Use LlamaIndex for retrieval, LangGraph for orchestration.

```python
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.core.agent import ReActAgent
from llama_index.core.tools import QueryEngineTool

documents = SimpleDirectoryReader("data").load_data()
index = VectorStoreIndex.from_documents(documents)
query_tool = QueryEngineTool.from_defaults(index.as_query_engine(), name="docs", description="Search documents")

agent = ReActAgent.from_tools([query_tool], verbose=True)
response = agent.chat("What does the document say about X?")
```

---

## Mastra

**Architecture:** TypeScript-native agent framework with workflows, RAG, memory.
**License:** Elastic License 2.0 (ELv2) | **Stars:** ~25K | **Language:** TypeScript
**Best for:** TypeScript/JS teams, Next.js integration, Replit users.

**Core concepts:**
- Agent: instructions + tools + model
- Workflow: step-based with branching and parallel
- RAG: built-in vector store integration
- Memory: conversation + semantic

**When to choose:** TypeScript team, JS-first stack, need full-stack framework in one language.

**When NOT to choose:**
- Python team (use LangGraph — larger ecosystem, more examples)
- Need advanced graph-based orchestration (Mastra workflows are simpler than LangGraph StateGraph)
- Heavy document processing or RAG (use LlamaIndex)

```typescript
import { Agent } from "@mastra/core";

const agent = new Agent({
  name: "researcher",
  instructions: "You are a research assistant.",
  model: "gpt-4o",
  tools: [searchTool],
});

const response = await agent.generate("Find the latest AI agent frameworks");
```

---

## Agno

**Architecture:** Model-driven, model-agnostic with built-in toolkits.
**License:** Apache 2.0 | **Stars:** ~37K | **Language:** Python
**Best for:** Model-agnostic deployments, persistent learning memory, many built-in tools.

**Key differentiator:** `learning=True` enables self-editing persistent memory that improves over time.
**When to choose:** Need true model agnosticism + persistent learning + many pre-built tools.

**When NOT to choose:**
- Need explicit graph-based orchestration (Agno is model-driven, no state machine)
- Need durable execution with checkpointing (use LangGraph)
- Enterprise compliance requirements (smaller community, less battle-tested than LangChain)

```python
from agno.agent import Agent
from agno.models.anthropic import Claude

agent = Agent(
    model=Claude(id="claude-sonnet-4-6-20250514"),
    instructions="You are a helpful assistant.",
    tools=[search_tool],
    learning=True,  # persistent memory
)
agent.print_response("Find the latest AI agent frameworks")
```

---

## Smolagents

**Architecture:** Model-driven, minimalist, open-model focused.
**License:** Apache 2.0 | **Stars:** ~25K | **Language:** Python
**Best for:** Research, open/local models, HuggingFace ecosystem.

**Key differentiator:** Code-first tool execution (model writes Python, framework executes it).
**When to choose:** Research/experimentation, open-model focus, HuggingFace integration.

**When NOT to choose:**
- Production deployment with strict security requirements (code execution is inherently risky)
- Need complex multi-agent orchestration (Smolagents is single-agent focused)
- Need enterprise support or large community ecosystem

```python
from smolagents import CodeAgent, tool, HfApiModel

@tool
def search(query: str) -> str:
    """Search the web for information."""
    return f"Results for: {query}"

agent = CodeAgent(tools=[search], model=HfApiModel())
result = agent.run("Find the latest AI agent frameworks")
```

---

## DSPy

> **Deep-dive reference:** `references/dspy.md` covers Signatures, Modules, optimizer selection, RAG patterns, multi-agent composition, and integration with orchestration frameworks.

**Architecture:** Optimization-first. Replace manual prompts with compiled signatures.
**License:** MIT | **Stars:** ~29K | **Language:** Python
**Best for:** Prompt optimization, systematic prompt engineering replacement.

**Core concepts:**
- Signature: input/output specification (not a prompt)
- Module: composable computation unit
- Optimizer: automatically finds best prompts/examples
- Teleprompter: specific optimization strategy

**When to choose:** Manually tweaking prompts, need systematic optimization (66% -> 87% on RAG benchmarks).
**Not a replacement for orchestration frameworks.** Complements them by optimizing LLM calls within agents.

**When NOT to choose:**
- Need agent orchestration (DSPy optimizes prompts, not workflows — combine with LangGraph)
- Small number of prompts that are already performing well (optimization overhead not justified)
- Need interpretable, hand-crafted prompts (compiled signatures are opaque)

```python
import dspy

lm = dspy.LM("anthropic/claude-sonnet-4-6-20250514")
dspy.configure(lm=lm)

classify = dspy.Predict("sentence -> sentiment: str")
result = classify(sentence="This framework is excellent")
print(result.sentiment)
```

---

## Head-to-Head

### LangGraph vs CrewAI
- **LangGraph**: Explicit control, cycles, durable execution, checkpointing, production state management.
- **CrewAI**: Rapid development, role-based teams, sequential/hierarchical processes.

### LangGraph vs Strands
- **LangGraph**: Explicit graph definitions, fine-grained state transitions, durable checkpointing, HITL interrupt/resume.
- **Strands**: Model-driven, minimal boilerplate, native AWS deployment (AgentCore), built-in multi-agent (Swarm/Graph/Workflow), native MCP + A2A. Days vs months time-to-production.

### LangChain vs LlamaIndex
- **LangChain**: Broadest integration ecosystem, general-purpose.
- **LlamaIndex**: RAG-heavy, complex document processing. Many teams use both.

### OpenAI SDK vs Strands
- **OpenAI SDK**: OpenAI-centric, built-in voice/realtime, minimal deployment needs.
- **Strands**: Multi-model, AWS-native (AgentCore managed runtime), built-in multi-agent patterns, native MCP + A2A protocol.

### Mastra vs Vercel AI SDK
- **Mastra**: Complete framework (agents, workflows, RAG, memory).
- **Vercel AI SDK**: Streaming-first UI with React/Next.js (2.8M vs 220K weekly downloads). Many use both.

---

## Key Trends Affecting Framework Choice (2025-2026)

1. **MCP as universal standard.** 97M monthly SDK downloads. Supported by all major frameworks. Non-negotiable for tool connectivity.
2. **Model-driven architectures gaining ground.** Strands' success validates that modern LLMs can drive planning without rigid workflows.
3. **Open-closed model gap closing.** Performance difference reduced from 8% to 1.7%. True model agnosticism is practical.
4. **Framework consolidation.** Microsoft merged AutoGen + Semantic Kernel. LangChain ceded orchestration to LangGraph. New entrants target specific developer communities.
