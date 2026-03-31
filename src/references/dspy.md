# DSPy Reference

Implementation reference for building agents with DSPy. Use when the framework decision (Step 3) selects DSPy for prompt optimization, or when combining DSPy with an orchestration framework (LangGraph, Strands) to optimize LLM calls within agents.

## Table of Contents

1. [When This Reference Applies](#when-this-reference-applies)
2. [Core Architecture](#core-architecture)
3. [Signatures](#signatures)
4. [Modules](#modules)
5. [Tools and Agents](#tools-and-agents)
6. [Optimizer Selection](#optimizer-selection)
7. [Evaluation](#evaluation)
8. [RAG Patterns](#rag-patterns)
9. [Multi-Agent Composition](#multi-agent-composition)
10. [Integration with Orchestration Frameworks](#integration-with-orchestration-frameworks)
11. [Observability](#observability)
12. [Deployment](#deployment)
13. [Production Project Structure](#production-project-structure)
14. [Pattern Mapping](#pattern-mapping)

---

## When This Reference Applies

Use DSPy when ALL of these hold:
- Prompt quality is a bottleneck (manual tuning has hit diminishing returns)
- You have a measurable metric to optimize against
- You have training examples (as few as 5-10, ideally 50+)
- You want model-portable prompts (compiled prompts transfer across LLMs)

Do NOT use DSPy when:
- You need agent orchestration (DSPy optimizes prompts, not workflows — pair with LangGraph or Strands)
- You have a small number of prompts already performing well (optimization overhead not justified)
- You need interpretable, hand-crafted prompts (compiled signatures are opaque)
- Your system has no measurable quality metric (optimizers need a target)

**Key mental model:** DSPy is to prompts what a compiler is to source code. You declare *what* you want (via Signatures), DSPy figures out *how* to prompt for it, and optimizers improve it automatically.

**Version:** 3.1.x (Python >= 3.9) | **License:** MIT

---

## Core Architecture

DSPy separates AI system design into three layers:

| Layer | Concept | Role |
|---|---|---|
| **Interface** | Signature | Declares input/output behavior — no prompt text |
| **Strategy** | Module | Wraps a prompting technique (CoT, ReAct, Refine) around a Signature |
| **Optimization** | Optimizer | Tunes instructions and few-shot examples to maximize a metric |

**Design principle:** The separation of interface from implementation means you can change the model, the prompting strategy, or the optimization approach independently. This is the core value proposition over manual prompt engineering.

### Configuration

```python
import dspy

# Configure with any supported provider (OpenAI, Anthropic, Google, Ollama, Azure)
lm = dspy.LM("anthropic/claude-sonnet-4-6-20250514")
dspy.configure(lm=lm)

# Multiple LMs for cost optimization
strong_lm = dspy.LM("anthropic/claude-sonnet-4-6-20250514")
cheap_lm  = dspy.LM("openai/gpt-4o-mini")
dspy.configure(lm=cheap_lm)  # default for most modules; override per-call
```

---

## Signatures

A Signature declares input/output behavior without specifying prompt text. DSPy expands it into a prompt and parses typed outputs automatically.

### Inline (quick prototyping)

```python
# Minimal
predictor = dspy.Predict("question -> answer")

# Typed outputs
predictor = dspy.Predict("document -> topics: list[str], sentiment: bool")
```

### Class-based (production use)

```python
from typing import Literal

class ClassifyReview(dspy.Signature):
    """Classify the sentiment and urgency of a customer review."""
    review: str = dspy.InputField(desc="The customer review text")
    product_category: str = dspy.InputField(desc="Category of the reviewed product")
    sentiment: Literal["positive", "neutral", "negative"] = dspy.OutputField()
    urgency: Literal["low", "medium", "high"] = dspy.OutputField()
    summary: str = dspy.OutputField(desc="One-sentence summary")
```

### Pydantic output (structured extraction)

```python
from pydantic import BaseModel

class Invoice(BaseModel):
    vendor: str
    date: str
    total: float
    line_items: list[str]

class ExtractInvoice(dspy.Signature):
    """Extract structured data from an invoice document."""
    document: str = dspy.InputField()
    invoice: Invoice = dspy.OutputField()
```

**Design rule:** Use class-based Signatures for any production code. Inline notation is for exploration only.

---

## Modules

Modules wrap prompting strategies around Signatures. They have learnable parameters (instructions + few-shot demos) and compose like PyTorch's `nn.Module`.

| Module | Strategy | When to Use |
|---|---|---|
| `dspy.Predict` | Direct prediction | Baseline, classification, extraction |
| `dspy.ChainOfThought` | Adds reasoning step before output | Reasoning-heavy tasks, QA, analysis |
| `dspy.ReAct` | Reason + Act loop with tools | Agentic tasks requiring tool use |
| `dspy.ProgramOfThought` | Generates and executes Python code | Math, data analysis, computation |
| `dspy.Refine` | Iterative refinement with reward signal | Quality-sensitive outputs |
| `dspy.BestOfN` | Generate N candidates, pick best | When variance is high |
| `dspy.MultiChainComparison` | Multiple reasoning chains, synthesize | Complex reasoning with multiple angles |
| `dspy.CodeAct` | Code generation + execution agent | Code-heavy tasks |
| `dspy.Reasoning` | Native CoT from reasoning models (o1, o3) | When using reasoning-native models |

### Module Composition

```python
class RAGPipeline(dspy.Module):
    def __init__(self, retriever, k=3):
        self.retriever = retriever
        self.generate = dspy.ChainOfThought("context, question -> answer")

    def forward(self, question: str):
        context = self.retriever(question, k=self.k)
        return self.generate(context=context, question=question)
```

**Key pattern:** Modules compose into programs via `dspy.Module`. Each sub-module's prompts are independently optimizable.

---

## Tools and Agents

Tools are plain Python functions with type hints. The docstring becomes the tool description for the LLM.

```python
def search_web(query: str) -> str:
    """Search the web for current information on a topic."""
    return web_search_api(query)

agent = dspy.ReAct(
    "user_request -> response",
    tools=[search_web, get_stock_price, execute_sql],
    max_iters=10
)
```

### MCP Integration (3.0+)

```python
from dspy.tools.mcp import MCPToolset

toolset = MCPToolset.from_server(server_command="uvx", server_args=["your-mcp-server@latest"])
agent = dspy.ReAct("question -> answer", tools=toolset.as_tools())
```

**Design rule:** Same tool design principles from `references/production.md` apply — one tool = one action, clear docstrings, minimize action space.

---

## Optimizer Selection

Optimizers tune prompt instructions and/or few-shot examples to maximize a metric. This is DSPy's unique capability — no other framework has built-in optimization.

### Decision Tree

```
Do you have labeled examples?
├── No
│   └── BootstrapFewShot (self-supervised via bootstrapping)
│
├── Yes (few, <50)
│   ├── Want instruction optimization? → MIPROv2 (auto="light")
│   ├── Want reflective/evolutionary?  → GEPA
│   └── Want mini-batch stochastic?    → SIMBA
│
└── Yes (many, 200+)
    ├── Want few-shot synthesis?   → BootstrapFewShotWithRandomSearch
    ├── Want full instruction opt? → MIPROv2 (auto="medium" or "heavy")
    ├── Want finetuning?           → BootstrapFinetune
    └── Want both?                 → BetterTogether
```

### Optimizer Reference

| Optimizer | Type | Best For | Cost Estimate |
|---|---|---|---|
| **MIPROv2** | Instructions + few-shot | General-purpose prompt optimization | ~$2 / 20min (light) |
| **GEPA** | Reflective evolution | Tasks with textual feedback; beats RL | Varies by iterations |
| **SIMBA** | Mini-batch incremental | Complex tasks, limited data | Low |
| **BootstrapFewShot** | Few-shot | Quick start, no labels needed | Minimal |
| **BootstrapFinetune** | Weight tuning | LM weight finetuning | Model-dependent |
| **BetterTogether** | Prompt + weights | Joint optimization | Highest |

### Optimization Pattern

```python
from dspy.teleprompt import MIPROv2

# 1. Define metric
def my_metric(example, prediction, trace=None):
    return float(example.answer.lower() in prediction.answer.lower())

# 2. Prepare data
trainset = [dspy.Example(question=q, answer=a).with_inputs("question") for q, a in data]

# 3. Optimize
optimizer = MIPROv2(metric=my_metric, auto="light", num_threads=8)
optimized = optimizer.compile(student=my_program, trainset=trainset, valset=devset)

# 4. Save compiled program
optimized.save("optimized_program.json")
```

**When NOT to optimize:**
- Fewer than 5 training examples (not enough signal)
- Already achieving >95% on your metric (diminishing returns)
- Prompts change frequently during development (optimize after stabilization)

---

## Evaluation

Always establish a baseline before optimizing. DSPy's evaluation framework mirrors the principles in `references/evals.md`.

```python
from dspy.evaluate import Evaluate

evaluate = Evaluate(devset=devset, metric=my_metric, num_threads=8, display_progress=True)
baseline_score = evaluate(my_program)
```

### Built-in Metrics

| Metric | Use Case |
|---|---|
| `answer_exact_match` | Exact string match |
| `answer_passage_match` | Answer appears in retrieved passages |
| `SemanticF1` | Semantic similarity via LM judge |
| `CompleteAndGrounded` | Completeness + groundedness (citation-aware) |

### LM-as-Judge Pattern

```python
class JudgeSignature(dspy.Signature):
    """Judge whether the predicted answer matches the gold answer."""
    gold_answer: str = dspy.InputField()
    predicted_answer: str = dspy.InputField()
    score: float = dspy.OutputField(desc="Float 0.0-1.0 measuring correctness")

judge = dspy.ChainOfThought(JudgeSignature)

def llm_judge_metric(example, prediction, trace=None):
    result = judge(gold_answer=example.answer, predicted_answer=prediction.answer)
    return result.score
```

**Design rule:** Define your metric before writing any module code. The metric drives everything — module selection, optimizer choice, and iteration decisions. See `references/evals.md` and `references/llm-as-judge.md` for comprehensive evaluation guidance.

---

## RAG Patterns

### Basic RAG

```python
class BasicRAG(dspy.Module):
    def __init__(self, retriever, k=3):
        self.retriever = retriever
        self.generate = dspy.ChainOfThought("context, question -> answer")

    def forward(self, question):
        passages = self.retriever(question)
        return self.generate(context="\n\n".join(passages[:3]), question=question)
```

### Multi-Hop RAG

```python
class MultiHopRAG(dspy.Module):
    def __init__(self, retriever, num_hops=3):
        self.retriever = retriever
        self.num_hops = num_hops
        self.generate_query = dspy.ChainOfThought("context, question -> search_query")
        self.generate_answer = dspy.ChainOfThought("context, question -> answer")

    def forward(self, question):
        context = ""
        for _ in range(self.num_hops):
            query = self.generate_query(context=context, question=question).search_query
            context += "\n\n" + "\n".join(self.retriever(query))
        return self.generate_answer(context=context, question=question)
```

### Agentic RAG (ReAct-powered)

```python
rag_agent = dspy.ReAct(
    dspy.Signature("question -> answer",
                   instructions="Use the search tools to find evidence before answering."),
    tools=[search_corpus, lookup_document],
    max_iters=8
)
```

**Key advantage:** All three RAG patterns are optimizable. MIPROv2 can improve retrieval query generation and answer synthesis prompts simultaneously.

---

## Multi-Agent Composition

DSPy supports multi-agent systems through module composition. Each agent is a `dspy.Module` with independently optimizable prompts.

### Router Pattern

```python
class RouterSignature(dspy.Signature):
    """Route a question to the appropriate specialist."""
    question: str = dspy.InputField()
    domain: Literal["finance", "medical", "legal"] = dspy.OutputField()

class MultiDomainAgent(dspy.Module):
    def __init__(self):
        self.router = dspy.Predict(RouterSignature)
        self.agents = {
            "finance": FinanceAgent(),
            "medical": MedicalAgent(),
            "legal": LegalAgent(),
        }

    def forward(self, question):
        route = self.router(question=question)
        return self.agents[route.domain](question=question)
```

**Limitation:** DSPy's multi-agent is manual composition — no built-in graph execution, checkpointing, or HITL. For complex orchestration patterns (parallel fan-out, conditional cycles, durable execution), pair DSPy modules with LangGraph or Strands.

---

## Integration with Orchestration Frameworks

DSPy's primary integration value is as an **optimization layer** inside orchestration frameworks. Use DSPy to optimize individual LLM calls while the orchestration framework handles workflow logic.

### DSPy + LangGraph

Use DSPy modules as the LLM-calling layer inside LangGraph nodes:

```python
import dspy
from langgraph.graph import StateGraph

# DSPy handles optimized LLM calls
classifier = dspy.Predict(ClassifyIntent)
classifier.load("optimized_classifier.json")

generator = dspy.ChainOfThought("context, question -> answer")
generator.load("optimized_generator.json")

# LangGraph handles orchestration
def classify_node(state):
    result = classifier(query=state["query"])
    return {"intent": result.intent}

def generate_node(state):
    result = generator(context=state["context"], question=state["query"])
    return {"answer": result.answer}

graph = StateGraph(MyState)
graph.add_node("classify", classify_node)
graph.add_node("generate", generate_node)
# ... edges, conditions, etc.
```

### DSPy + Strands

Use DSPy-optimized prompts within Strands tool functions:

```python
from strands import Agent, tool

# DSPy-optimized classification
classifier = dspy.Predict(ClassifySignature)
classifier.load("optimized.json")

@tool
def classify_document(content: str) -> str:
    """Classify a document using optimized prompts."""
    result = classifier(document=content)
    return f"Category: {result.category}, Confidence: {result.confidence}"

agent = Agent(tools=[classify_document])
```

### When to Combine

| Scenario | Approach |
|---|---|
| Simple agent, prompts underperforming | DSPy alone (ReAct module) |
| Complex workflow, prompts fine | Orchestration framework alone |
| Complex workflow, prompts underperforming | Orchestration framework + DSPy modules at LLM call sites |
| Need to port prompts across models | DSPy (compiled signatures are model-portable) |

---

## Observability

### Usage Tracking

```python
dspy.configure(lm=lm, track_usage=True)

with dspy.track_usage() as usage:
    result = my_program(question="...")
print(usage)  # token counts per model
```

### Prompt Inspection

```python
result = my_module(question="What causes rain?")
dspy.inspect_history(n=3)  # inspect last N prompts sent to LM
```

### MLflow Integration

```python
import mlflow
mlflow.dspy.autolog()  # automatic tracing of all DSPy calls
```

---

## Deployment

### Save/Load Compiled Programs

```python
# Save (prompts + few-shot demos as JSON)
optimized_program.save("my_program.json")

# Load
program = MyDSPyProgram()
program.load("my_program.json")
```

### FastAPI Serving

```python
from fastapi import FastAPI
import dspy

app = FastAPI()
dspy.configure(lm=dspy.LM("openai/gpt-4o-mini"))

rag = RAGPipeline(retriever=my_retriever)
rag.load("optimized_rag.json")

@app.post("/query")
async def query(req: QueryRequest):
    result = rag(question=req.question)
    return {"answer": result.answer}
```

For full deployment patterns (Docker, monitoring, long-term memory), see `references/deployment.md`.

---

## Production Project Structure

```
my_dspy_project/
├── programs/           # dspy.Module subclasses
├── signatures/         # Signature classes (grouped by domain)
├── tools/              # Tool functions for ReAct agents
├── optimization/
│   ├── metrics.py      # Metric functions
│   ├── run_mipro.py    # MIPROv2 optimization script
│   └── run_gepa.py     # GEPA optimization script
├── data/
│   ├── trainset.jsonl
│   └── devset.jsonl
├── compiled/           # Saved optimized programs (.json)
├── config/             # LM configuration
├── tests/              # Baseline evaluation scripts
└── main.py             # Entry point / API server
```

---

## Failure Modes

| Failure Mode | Cause | Symptoms | Mitigation |
|---|---|---|---|
| **Optimizer convergence failure** | Too few examples, poor metric signal, overly complex search space | Optimized program performs worse than baseline or shows no improvement | Start with ≥200 labeled examples; use MIPROv2 with `num_threads=24`; verify metric function returns meaningful gradients |
| **Prompt drift** | Optimized prompts overfit to training distribution | High dev-set scores but production accuracy drops on novel inputs | Hold out a diverse test set; run walk-forward evaluation; re-optimize periodically on fresh production data |
| **Few-shot contamination** | Optimizer selects demos that leak answers or create shortcuts | Model appears to reason but is pattern-matching on demo structure | Inspect `dspy.inspect_history()`; verify demos don't contain target answers; use `max_bootstrapped_demos` conservatively |
| **Metric gaming** | Optimizer finds prompts that maximize metric without genuine quality | High metric scores but outputs are degenerate (e.g., always hedging, verbose padding) | Use multi-dimensional metrics; include human spot-checks; add length/format constraints to metric |
| **Cold-start with small data** | < 50 labeled examples for optimization | Optimizer has insufficient signal; random search dominates | Use `BootstrapFewShotWithRandomSearch` for small datasets; bootstrap from a strong teacher model; augment data before optimizing |
| **Module composition fragility** | Complex `forward()` chains with many sub-modules | One sub-module regression cascades through pipeline; hard to debug | Evaluate each sub-module independently; use `dspy.Assert` for intermediate checks; log per-module metrics |

---

## Pattern Mapping

How DSPy maps to the agent-builder pattern catalogue (`references/patterns.md`):

| Pattern | DSPy Support | Notes |
|---|---|---|
| **ReAct** | Native (`dspy.ReAct`) | Full support with tool use |
| **Reflection** | Via `dspy.Refine` or self-correcting pattern | Iterative refinement with reward signal |
| **Generator-Critic** | `dspy.BestOfN` or `dspy.Refine` | Generate + critique loop |
| **Plan-and-Execute** | Manual composition | Build as `dspy.Module` with planning + execution sub-modules |
| **Router** | `dspy.Predict` with routing Signature | Optimizable routing decisions |
| **Sequential** | Module composition in `forward()` | Chain modules in sequence |
| **Map-Reduce** | `dspy.Parallel` + aggregation module | Fan-out with parallel execution |
| **Parallel** | No built-in orchestration | Pair with LangGraph for true parallel fan-out/fan-in |
| **Loop** | No built-in orchestration | Pair with LangGraph for conditional cycles |
| **Network/Swarm** | No built-in orchestration | Pair with LangGraph or Strands |
| **HITL** | No support | Use LangGraph |
| **Tool Use** | Native | Plain functions with type hints |

**Summary:** DSPy natively supports behavioral patterns (ReAct, Reflection, Generator-Critic) and simple data flow (Sequential, Map-Reduce). For topology patterns requiring orchestration (Parallel, Loop, Network, HITL), pair with an orchestration framework.
