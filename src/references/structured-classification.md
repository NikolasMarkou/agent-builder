# Structured Classification Reference

LLM-based classification: mapping free-form input to predefined classes with validated JSON output. The foundational pattern behind Router topology agents, intent detection, and controlled flow routing.

## Table of Contents

1. [When to Use](#when-to-use)
2. [Enforcement Mechanisms](#enforcement-mechanisms)
3. [Schema Design](#schema-design)
4. [Prompt Design for Classifiers](#prompt-design-for-classifiers)
5. [Implementation Patterns](#implementation-patterns)
6. [Handler Routing](#handler-routing)
7. [Multi-Intent and Hierarchical Classification](#multi-intent-and-hierarchical-classification)
8. [Constrained Decoding Engines](#constrained-decoding-engines)
9. [Failure Modes and Mitigations](#failure-modes-and-mitigations)
10. [Production Checklist](#production-checklist)

---

## When to Use

| Condition | Use Structured Classification | Alternative |
|---|---|---|
| Fixed, known set of intents | Yes | — |
| Need to route to downstream agent/handler | Yes | — |
| Inputs are messy/natural language | Yes | — |
| Zero labeled training data available | Yes | — |
| Classes change frequently | No | Embedding-based routing |
| Latency critical (<100ms) | No | Fine-tuned small model |
| >15 classes needed | Partially | Hierarchical classification (see below) |

**Design axiom — Tiered escalation:** Before reaching for an LLM classifier, check if deterministic routing (regex, keyword, URL path) handles 60%+ of your traffic. LLM classification should handle the ambiguous remainder, not every request.

---

## Enforcement Mechanisms

Two ways to guarantee schema compliance:

### 1. Prompt-Based (Soft Constraint)

The model is instructed to output a specific schema via the system prompt. No token-level enforcement.

**Risk:** Hallucinated field names, invalid enum values, freeform text leaking in.
**Mitigation:** JSON schema in the prompt, pre-filled assistant prefix (`{`), few-shot examples, output parsing with retry.

**When to use:** Prototyping, low-volume, or when using APIs without native structured output support.

### 2. Constrained Decoding (Hard Constraint)

A grammar engine masks invalid tokens at each decoding step, making schema deviation impossible. Output is guaranteed to conform.

**When to use:** Production systems, high-volume classification, any case where a malformed response causes downstream failure.

**Decision rule:** Use API-level structured outputs (OpenAI `response_format`, Anthropic via Instructor) for simplicity. Use constrained decoding engines (XGrammar, llguidance) for self-hosted deployments needing maximum throughput.

See [Constrained Decoding Engines](#constrained-decoding-engines) for engine comparison.

---

## Schema Design

### Step 1: Define Classes

Keep classes mutually exclusive and exhaustive. Always include a fallback.

```python
CLASSES = [
    "order_status",      # user asks about an order
    "product_info",      # user asks about a product
    "payment_issue",     # user reports a payment problem
    "return_request",    # user wants to return an item
    "general_support",   # anything else — the fallback
]
```

**Rules:**
- Max ~15 classes per classifier. Beyond that, use hierarchical classification.
- Always include `"other"` / `"fallback"` class. Without it, the model forces ambiguous inputs into wrong categories.
- Use `snake_case` identifiers — maps directly to handler function names.

### Step 2: Design the Output Schema

```json
{
  "type": "object",
  "properties": {
    "reasoning": {
      "type": "string",
      "description": "Chain-of-thought explanation before the classification decision"
    },
    "intent": {
      "type": "string",
      "enum": ["order_status", "product_info", "payment_issue", "return_request", "general_support"],
      "description": "The primary classified intent"
    },
    "confidence": {
      "type": "number",
      "minimum": 0.0,
      "maximum": 1.0,
      "description": "Model confidence in this classification"
    },
    "entities": {
      "type": "object",
      "description": "Extracted entities relevant to the intent",
      "additionalProperties": { "type": "string" }
    }
  },
  "required": ["reasoning", "intent", "confidence", "entities"],
  "additionalProperties": false
}
```

**Critical: `reasoning` before `intent`.** Constrained decoding distorts probability distributions. Letting the model reason first inside the structured format mitigates classification degradation. This is the same principle as Chain-of-Thought — the model makes better decisions after explaining its thinking.

---

## Prompt Design for Classifiers

The classifier system prompt is the most critical component of the Router pattern (see `patterns.md` §1.4).

```
You are an intent classification engine. Analyze the user's message and
classify it into exactly one of the following intents:

- order_status: User is asking about the status, delivery, or tracking of an order
- product_info: User is asking about product details, specs, or availability
- payment_issue: User is reporting a payment failure, charge dispute, or billing error
- return_request: User wants to initiate or track a product return
- general_support: Any query that does not fit the above categories

Rules:
1. Output ONLY valid JSON matching the provided schema.
2. Set confidence between 0.0 and 1.0 based on how clear the intent is.
3. Extract any relevant entities (e.g., order IDs, product names, amounts).
4. Use "general_support" when intent is ambiguous or multi-topic.
5. Write your reasoning before selecting the intent.
```

**Design principles:**
- Each class gets a one-line definition — unambiguous, mutually exclusive.
- The fallback class definition explicitly says "any query that does not fit" — this anchors the model.
- Rules section enforces output discipline. Rule 5 triggers CoT before the decision.
- For prompt structure details (delimiters, block ordering), see `prompt-structuring.md`.

---

## Implementation Patterns

### OpenAI Structured Outputs (API-Level)

```python
from openai import OpenAI
from pydantic import BaseModel, Field
from enum import Enum

client = OpenAI()

class Intent(str, Enum):
    order_status = "order_status"
    product_info = "product_info"
    payment_issue = "payment_issue"
    return_request = "return_request"
    general_support = "general_support"

class ClassificationResult(BaseModel):
    reasoning: str = Field(description="Step-by-step reasoning before deciding the intent")
    intent: Intent
    confidence: float = Field(ge=0.0, le=1.0)
    entities: dict[str, str] = Field(default_factory=dict)

def classify_intent(user_message: str) -> ClassificationResult:
    response = client.beta.chat.completions.parse(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_message},
        ],
        response_format=ClassificationResult,
    )
    return response.choices[0].message.parsed
```

### Anthropic (with Instructor)

```python
import anthropic
import instructor
from pydantic import BaseModel, Field
from enum import Enum

client = instructor.from_anthropic(anthropic.Anthropic())

class ClassificationResult(BaseModel):
    reasoning: str
    intent: Intent  # Same enum as above
    confidence: float = Field(ge=0.0, le=1.0)
    entities: dict[str, str] = Field(default_factory=dict)

def classify_intent(user_message: str) -> ClassificationResult:
    return client.messages.create(
        model="claude-sonnet-4-6-20250514",
        max_tokens=512,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
        response_model=ClassificationResult,
    )
```

### Self-Hosted (vLLM + XGrammar)

```python
from openai import OpenAI
import json

client = OpenAI(base_url="http://localhost:8000/v1", api_key="token")

response = client.chat.completions.create(
    model="meta-llama/Llama-3.1-8B-Instruct",
    messages=[
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_message},
    ],
    response_format={
        "type": "json_schema",
        "json_schema": {"name": "intent_classification", "schema": json_schema}
    },
)

result = json.loads(response.choices[0].message.content)
```

### LangGraph Router Integration

This is how structured classification plugs into the Router topology pattern from `patterns.md`:

```python
from langgraph.graph import StateGraph, START, END
from pydantic import BaseModel, Field
from enum import Enum

class Intent(str, Enum):
    billing = "billing"
    technical = "technical"
    general = "general"

class RouterDecision(BaseModel):
    reasoning: str
    intent: Intent
    confidence: float = Field(ge=0.0, le=1.0)

def router_node(state):
    """Classify intent using structured output, then route."""
    structured_llm = model.with_structured_output(RouterDecision)
    decision = structured_llm.invoke([
        SystemMessage(content=ROUTER_PROMPT),
        HumanMessage(content=state["user_input"]),
    ])
    return {"intent": decision.intent, "confidence": decision.confidence}

def route_by_intent(state) -> str:
    if state["confidence"] < 0.6:
        return "clarification"
    return {
        "billing": "billing_agent",
        "technical": "tech_agent",
        "general": "faq_agent",
    }[state["intent"]]

builder = StateGraph(State)
builder.add_node("router", router_node)
builder.add_node("billing_agent", billing_handler)
builder.add_node("tech_agent", tech_handler)
builder.add_node("faq_agent", faq_handler)
builder.add_node("clarification", clarification_handler)

builder.add_edge(START, "router")
builder.add_conditional_edges("router", route_by_intent)
```

---

## Handler Routing

Once classified, route to the appropriate handler. This is the bridge between classification and agent execution:

```python
from typing import Callable

HANDLER_REGISTRY: dict[str, Callable] = {
    "order_status":    handle_order_status,
    "product_info":    handle_product_info,
    "payment_issue":   handle_payment_issue,
    "return_request":  handle_return_request,
    "general_support": handle_general_support,
}

def route_and_execute(user_message: str) -> str:
    result = classify_intent(user_message)

    if result.confidence < 0.6:
        return ask_for_clarification(user_message)

    handler = HANDLER_REGISTRY.get(result.intent, handle_general_support)
    return handler(user_message, result.entities)
```

**Confidence thresholding:** Set a minimum confidence (recommend 0.6) below which the system asks for clarification instead of routing to a potentially wrong handler. This prevents silent misroutes.

---

## Multi-Intent and Hierarchical Classification

### Multi-Intent

When a single message contains multiple intents (e.g., "Where's my order and can I return the charger?"):

```python
class IntentScore(BaseModel):
    intent: Intent
    confidence: float = Field(ge=0.0, le=1.0)
    entities: dict[str, str] = Field(default_factory=dict)

class MultiClassificationResult(BaseModel):
    reasoning: str
    intents: list[IntentScore] = Field(
        min_length=1,
        max_length=3,
        description="Ranked list of detected intents, most probable first"
    )
```

**When to use:** Only if your domain commonly produces compound queries. Adds complexity to the handler routing layer — each intent needs separate execution and result aggregation.

**When NOT to use:** Most domains. Single-intent classification with a fallback handles 90%+ of cases.

### Hierarchical Classification

For large class sets (>15), use a two-stage router:

```
User Input
    │
    ▼
Stage 1: Domain Classifier (5 broad classes)
    ["billing", "shipping", "product", "account", "other"]
    │
    ▼
Stage 2: Intent Classifier (domain-specific, 5-10 classes each)
    billing  → ["payment_failure", "refund_request", "invoice_query", ...]
    shipping → ["tracking", "delivery_issue", "address_change", ...]
```

**Why it works:** Each classifier stays within the reliable range (~15 classes). Domain-specific prompts improve accuracy on specialized terminology. Total classes can scale to 50+ without degradation.

**Cost trade-off:** Two LLM calls per classification. Mitigate by using a smaller/faster model for Stage 1 (domain routing is usually easy).

**LangGraph implementation:** Stage 1 is a Router node, Stage 2 nodes are themselves Routers or direct handlers — nested conditional edges.

---

## Constrained Decoding Engines

For self-hosted deployments, these engines guarantee schema compliance at the token level:

| Engine | Backend | Used By | Overhead/Token | Best For |
|---|---|---|---|---|
| **XGrammar** | Push-Down Automata | vLLM (default), SGLang | <40µs | Production vLLM/SGLang |
| **llguidance** | Rust/Earley Parser | OpenAI (credited), Azure | ~50µs | OpenAI backend, Azure |
| **Guidance** | Mixed | Research | Medium | Complex grammars, research |
| **Outlines** | Finite State Machine | Self-hosted | High (large enums) | Simple schemas only |
| **Instructor** | API wrapper | OpenAI, Anthropic, Gemini | None (API-level) | High-level Pydantic interface |

**Tooling decision tree:**

```
Do you self-host the model?
├── No (API)
│   ├── OpenAI    → beta.chat.completions.parse() with Pydantic
│   ├── Anthropic → Instructor + from_anthropic()
│   └── Google    → Instructor + from_google()
└── Yes (self-hosted)
    ├── vLLM      → response_format with json_schema (XGrammar backend)
    ├── SGLang    → constrained_decoding with XGrammar
    └── llama.cpp → grammar= parameter with GBNF schema
```

---

## Failure Modes and Mitigations

| Failure Mode | Cause | Mitigation |
|---|---|---|
| Hallucinated intent values | No schema enforcement | Use `enum` in schema + constrained decoding |
| Silent misroute on edge cases | Low confidence not caught | Confidence threshold (< 0.6) + clarification fallback |
| Misclassification with many classes | >15 classes overwhelm the model | Hierarchical classification |
| Token cost from reasoning field | CoT adds ~100-200 tokens | Set `max_tokens` budget (≤512); skip reasoning in high-volume paths |
| Schema compilation timeout | Large enum (>50 values) | Use XGrammar over Outlines |
| Multi-intent forced into single class | Compound user queries | Add multi-intent schema variant |
| Classification drift over time | User language evolves | Log all classifications; review prompt quarterly |
| Router oscillation | Overlapping categories | Clearer category definitions, fallback category (see `patterns.md` failure modes) |

---

## Production Checklist

- [ ] Classes are mutually exclusive and cover all expected inputs
- [ ] Fallback `"other"` class is defined
- [ ] Schema uses `"additionalProperties": false`
- [ ] `reasoning` field precedes `intent` field in schema (CoT before decision)
- [ ] Confidence threshold defined (< 0.6 triggers clarification)
- [ ] Handler registry maps every class to a function
- [ ] Classification results are logged with user input for drift detection
- [ ] Schema tested against edge cases before deployment
- [ ] Token budget set (`max_tokens` ≤ 512 for classification tasks)
- [ ] Error handling wraps JSON parsing for prompt-only approaches
- [ ] Deterministic routing checked first (design axiom: tiered escalation)
