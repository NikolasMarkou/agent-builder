# Production Reference

Everything needed to take an agent from prototype to production. Covers context engineering, tool design, evaluation, cost modeling, observability, guardrails, and failure modes.

## Table of Contents

1. [The Reality Check](#the-reality-check)
2. [Context Engineering](#context-engineering)
3. [Tool Design Principles](#tool-design-principles)
4. [Evaluation Strategy](#evaluation-strategy)
5. [Cost Modeling](#cost-modeling)
6. [Observability](#observability)
7. [Guardrails](#guardrails)
8. [Production Failure Modes](#production-failure-modes)
9. [Deployment Checklist](#deployment-checklist)

---

## The Reality Check

| Source | Finding |
|---|---|
| Deloitte 2025 | Only 11% of organizations have agents in production |
| McKinsey | Fewer than 10% have scaled multi-agent systems |
| Cleanlab/MIT (1,837 surveyed) | Only 95 had agents live in production |
| Gartner | 40%+ of agentic AI projects will fail by 2027 |

The gap between demo and production is where most fail. Production failures are rarely model quality. They are architectural decisions.

---

## Context Engineering

Prompt engineering is insufficient for agents operating across multi-session workflows. The real constraint is context management.

### Central Thesis

**Keep context small, truth central, and gates explicit.**

> **Design axiom: Minimize context.** The 100:1 input-to-output ratio in agents means optimizing input tokens is 100x more impactful than optimizing output. Format choice alone swings accuracy 15-20pp (`tabular-data.md`). Cheap deterministic tools eliminate tokens before they reach the LLM (`text-tools.md`).

### Context vs Prompt Engineering

| Dimension | Prompt Engineering | Context Engineering |
|---|---|---|
| Scope | Single instruction | Entire information state across all inference calls |
| Optimization target | Wording | Token allocation against finite attention budget |
| Failure mode | Poor single-call quality | Context rot, numeric drift, state incoherence over time |

### Context Rot

The temporal degradation of response quality as context grows. Manifests as: forgotten constraints, contradicted prior decisions, hallucinated numbers.

Causes:
- O(n^2) attention scaling makes long contexts unreliable
- "Lost in the middle" effect: models fixate on early/late tokens, ignore middle
- Stale tool outputs, deprecated state polluting the window
- KV-cache invalidation from even single token changes

### The Three-Artefact Architecture (Sood 2025)

Validated in 60 live sessions. Enforces text-number-cadence separation:

| Artefact | Contains | Does Not Contain |
|---|---|---|
| **Strategy Master** | Narrative reasoning, rules, procedures | Live numerics |
| **Canonical Numbers Sheet** | Every numeric truth: targets, rates, thresholds | Interpretation, rationale |
| **Life System Master** | Cadence schedules, audit procedures, governance | Content, numbers |

Any number absent from the Canonical Numbers Sheet is `NON-CANONICAL` and cannot drive decisions.

### Context Budget Rules

1. **System prompt**: Static instructions, persona, constraints. Cache-friendly. Front-load.
2. **Retrieved context**: RAG results, tool outputs. Place close to the query. Compress aggressively.
3. **Conversation history**: Summarize old turns. Keep recent turns verbatim.
4. **Working memory**: Current task state. Most volatile, most important.

**Manus finding:** Input-to-output ratio in agents is ~100:1. Optimizing input tokens is far more impactful than optimizing output.

### Practical Controls

- **SummarizationMiddleware**: Auto-compress history on context overflow
- **ContextEditingMiddleware**: Programmatic history editing before model calls
- **State checkpointing**: Persist state externally, load minimal subset per call
- **Tool output compression**: Truncate verbose tool results to essential data
- **Semantic deduplication**: Remove redundant information across messages

```python
from langchain.agents import create_agent
from langchain.agents.middleware import SummarizationMiddleware, ContextEditingMiddleware

# Auto-summarize when context exceeds model window
agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[...],
    middleware=[SummarizationMiddleware()],  # triggers on ContextOverflowError
)

# Or: manual tool output truncation in a custom node
def truncate_tool_output(output: str, max_chars: int = 2000) -> str:
    if len(output) <= max_chars:
        return output
    return output[:max_chars] + f"\n... truncated ({len(output)} chars total)"
```

---

## Tool Design Principles

From Claude Code production learnings (Anthropic, Feb 2026).

### Principle 1: Minimize the Action Space

Every tool is a choice evaluated on every turn. Tool count has non-linear cost.

Before adding a tool, exhaust alternatives:
- Extend an existing tool's parameters
- Progressive disclosure (meta-tool that lists advanced tools)
- Subagent (capability requiring its own context)
- System prompt instruction

Claude Code runs ~20 tools and actively questions whether all are necessary.

### Principle 2: Shape Tools to Model Capabilities

A tool that helps a weaker model can constrain a stronger one. Revisit tool design every major model update.

Example: Claude Code evolved from TodoWrite + system reminders -> TodoWrite alone -> Task tool with dependencies + subagent coordination as model capabilities improved.

### Principle 3: Design for Elicitation

Getting the model to ask the right questions is as important as getting it to take the right actions.

**What works:** Dedicated `AskUserQuestion` tool with structured fields (question text, options array, allow freeform flag).
**What fails:** Adding a `questions` parameter to an existing tool (semantic conflict), custom markdown output parsing (fragile).

One clear semantic purpose per tool.

### Principle 4: Progressive Disclosure

Hide rarely-needed tools behind a "list advanced tools" meta-tool. Reduces cognitive overhead on most turns, maintains access when needed.

### Principle 5: Instrument Everything

Every tool call should emit structured telemetry: tool name, input hash, output hash, latency, success/failure, retry count. This is non-negotiable for production debugging.

---

## Evaluation Strategy

> **For comprehensive evaluation guidance** — frameworks, benchmarks, metrics, LLM-as-judge, safety evals, monitoring tooling, and building eval pipelines — read `evals.md`. This section provides a quick production-context summary.

**Key principles for production evaluation:**

1. **Domain-specific evals first.** Generic benchmarks tell you nothing about your use case. Build evaluation datasets from real user interactions.
2. **Human-in-the-loop during ramp-up.** Start with 100% human review, gradually reduce as confidence builds.
3. **LLM-as-judge for scale.** Calibrate against human judgments. See `llm-as-judge.md` for implementation.
4. **A/B testing in production.** Shadow mode first, then canary, then full rollout.
5. **The learning loop.** Every user correction is signal. Log corrections, feed back into prompts, track correction rate over time.

---

## Cost Modeling

> **Design axiom: Model costs first.** Token costs multiply through loops, fan-out, and multi-step workflows. A 50x single-call cost difference (`text-tools.md`) becomes a 50,000x difference at scale. A 100x per-comparison difference (`entity-resolution.md`) means $150 vs $10,000 per run. Always calculate before building.

### Token Math at Scale

```
Monthly cost = (avg_input_tokens + avg_output_tokens) × price_per_token × monthly_invocations
             + tool_call_costs + embedding_costs + infrastructure
```

Example: Agent averaging 5,000 input + 1,000 output tokens per invocation, using Claude Sonnet at $3/$15 per million tokens, running 100K times/month:
- Input: 5,000 × $3/1M × 100,000 = $1,500
- Output: 1,000 × $15/1M × 100,000 = $1,500
- Total LLM alone: $3,000/month

### Cost Reduction Levers

1. **Prompt caching** (Anthropic): Cache static system prompt portions. Can reduce input costs significantly.
2. **Model routing**: Use cheaper models for simple tasks, expensive models only when needed. `ModelFallbackMiddleware` or custom routing middleware.
3. **Context compression**: Shorter context = lower cost. SummarizationMiddleware.
4. **Batch processing**: Use Batch API for non-realtime workloads (typically 50% cheaper).
5. **Tool output truncation**: Don't send 10KB tool results when 500 bytes suffices.
6. **Caching tool results**: If the same query hits the same tool repeatedly, cache the result.

---

## Observability

### Non-Negotiable Requirements

1. **Trace every invocation end-to-end.** Every LLM call, tool call, state transition, and edge decision.
2. **Structured logging.** JSON logs with: thread_id, node_name, tool_name, input_hash, output_hash, latency_ms, token_count, error_type.
3. **Cost tracking per invocation.** Know what each agent run costs.
4. **Alerting on anomalies.** Spike in token usage, error rates, latency.

### LangSmith

The default observability layer for LangChain/LangGraph:

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY=your_key
```

Features: detailed execution traces, state transitions, evaluation datasets, prompt management, cost tracking, HIPAA/SOC 2/GDPR compliance.

### Structured Logging

Production agents need context-aware structured logging, not `print()` statements.

**Environment-based format:**

| Environment | Log Format | Log Level | Why |
|---|---|---|---|
| Development / Test | Console (human-readable) | DEBUG | Developer ergonomics |
| Staging / Production | JSON (machine-parseable) | WARNING | Parseable by log aggregators |

**Required context fields per log entry:** `thread_id`, `node_name`, `tool_name`, `latency_ms`, `token_count`, `error_type`. Use request-scoped context variables so these fields propagate automatically through the call stack without manual threading.

```python
import logging, json, time, contextvars

thread_id_var = contextvars.ContextVar("thread_id", default="unknown")

class AgentJsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "ts": record.created, "level": record.levelname,
            "thread_id": thread_id_var.get(),
            "node": getattr(record, "node", None),
            "tool": getattr(record, "tool", None),
            "latency_ms": getattr(record, "latency_ms", None),
            "tokens": getattr(record, "tokens", None),
            "msg": record.getMessage(),
        })

logger = logging.getLogger("agent")
handler = logging.StreamHandler()
handler.setFormatter(AgentJsonFormatter())
logger.addHandler(handler)
```

**Log rotation:** Daily rotation with environment-prefixed filenames. Retain 30 days in production.

### Metrics for Agents

Define and expose metrics that matter for agent operations:

| Metric | Type | Labels | What It Tells You |
|---|---|---|---|
| `http_requests_total` | Counter | method, endpoint, status | Traffic volume and error rates |
| `http_request_duration_seconds` | Histogram | method, endpoint | Latency distribution |
| `llm_inference_duration_seconds` | Histogram | model | Model performance (use buckets: 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0s) |
| `llm_tokens_total` | Counter | model, direction (input/output) | Token usage for cost tracking |
| `db_connections_active` | Gauge | — | Connection pool health |
| `agent_task_completion_total` | Counter | status (success/failure) | Agent reliability |

Expose via a `/metrics` endpoint. Scrape with Prometheus (or equivalent). See `deployment.md` for the full monitoring stack setup.

### Tracing Platforms

| Platform | Best For | Model |
|---|---|---|
| **LangSmith** | LangChain/LangGraph teams. Detailed execution traces, state transitions, eval datasets, cost tracking. HIPAA/SOC 2/GDPR. | Commercial (free tier: 5K traces) |
| **Langfuse** | Self-hosting, data sovereignty. Trace tracking, LLM-as-judge score persistence, session grouping. | Open-source (MIT) |
| **OpenTelemetry + OpenLLMetry** | Vendor-neutral. GenAI semantic conventions (v1.37+) with LLM-specific auto-instrumentation. | Open standard |
| **Arize Phoenix** | Production monitoring, drift detection. | OSS + commercial |

### For Non-LangChain Stacks

- OpenTelemetry integration (most frameworks support it)
- OpenLLMetry (Traceloop) extends OTel with LLM-specific auto-instrumentation
- Custom structured logging
- Dedicated agent monitoring (Arize, Langfuse, etc.)

---

## Guardrails

### Input Validation

- Classify input intent before routing to agent (see `structured-classification.md` for schema design, enforcement mechanisms, and confidence thresholding)
- Reject out-of-scope queries early (cheaper than letting the agent fail)
- PII detection and redaction (`PIIDetectionMiddleware`)
- Content moderation (`ContentModerationMiddleware`)

### Output Validation

- Schema validation for structured outputs
- Factual grounding checks (citations, source verification)
- Hallucination detection (compare against retrieved context)
- Toxicity/safety filters

### Tool Permission Scoping

- Principle of least privilege: agents should only access tools they need
- Read-only defaults: write operations require explicit grants
- Rate limiting per tool: prevent runaway API calls
- Authentication token scoping: narrow token permissions

### MCP Security

MCP is the universal tool standard but has security concerns:
- Prompt injection via tool outputs
- Tool permission exploitation
- Data exfiltration through tool calls
- Always validate and sanitize MCP tool outputs

---

## Security Hardening

### Input Sanitization

Every user-facing endpoint must sanitize before processing. Defense in depth — apply multiple layers at the system boundary, before data enters the agent pipeline:

| Layer | What It Does | Why |
|---|---|---|
| **Null byte stripping** | Remove `\x00` characters | Prevents null byte injection in downstream systems |
| **HTML encoding** | Escape `<`, `>`, `&`, `"`, `'` | Prevents XSS if output is rendered in a browser |
| **Script tag removal** | Strip `<script>...</script>` blocks | Defense against stored XSS |
| **Recursive sanitization** | Apply to nested dicts, lists, strings | User input arrives in complex structures (JSON bodies) |

**Key principle:** Sanitize at the boundary, not inside the pipeline. Every string from an external source (user input, tool output, webhook payload) passes through sanitization before entering the agent context.

### Rate Limiting

Per-endpoint rate limits prevent abuse and runaway costs.

**Recommended defaults:**

| Endpoint Type | Limit | Rationale |
|---|---|---|
| Chat (primary agent) | 30/minute | Balances usability with cost control |
| Streaming | 20/minute | Streaming holds connections longer |
| Authentication | 20/minute | Prevent credential stuffing |
| Account creation | 10/hour | Prevent account spam |
| Health checks | 60/minute | Allow frequent monitoring |

**Global fallback:** 200/day, 50/hour per IP. Relax to 1000/day in dev/test.

**Implementation:** Key rate limits on IP address for public endpoints. Key on authenticated user ID for post-auth endpoints. Return `429 Too Many Requests` with `Retry-After` header.

```python
from collections import defaultdict
import time

class RateLimiter:
    def __init__(self, max_calls: int, period_seconds: int):
        self.max_calls = max_calls
        self.period = period_seconds
        self.calls: dict[str, list[float]] = defaultdict(list)

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        self.calls[key] = [t for t in self.calls[key] if now - t < self.period]
        if len(self.calls[key]) >= self.max_calls:
            return False
        self.calls[key].append(now)
        # Evict stale keys to prevent unbounded memory growth
        if len(self.calls) > self.max_calls * 10:
            stale = [k for k, v in self.calls.items() if not v]
            for k in stale:
                del self.calls[k]
        return True

# Note: this in-memory implementation is single-process only.
# For multi-worker deployments, use Redis-based rate limiting.
# Usage in FastAPI:
# limiter = RateLimiter(max_calls=30, period_seconds=60)
# if not limiter.allow(request.client.host):
#     raise HTTPException(429, headers={"Retry-After": "60"})
```

### Authentication

For agent APIs exposed beyond localhost, use stateless JWT authentication:

- **Token creation:** Include `sub` (user ID), `iat` (issued at), `exp` (expiration). Sign with HS256 minimum.
- **Token verification:** Validate signature, check expiration, extract user context for downstream logging.
- **Token scope:** 30-day expiry for session tokens. Shorter (1-hour) for elevated-privilege operations.
- **Never** store tokens in local storage if serving a web frontend — use httpOnly cookies.

---

## LLM Service Resilience

### Model Registry with Fallback

Don't hardcode a single model. Maintain a registry of initialized model clients and fall back automatically on failure:

1. **Register** multiple models at startup (e.g., primary Claude Sonnet, fallback GPT-4o, cheap fallback GPT-4o-mini)
2. **Circular fallback:** On failure, try the next registered model. Wrap around the list before giving up.
3. **Separate concerns:** The registry manages model instances. The caller doesn't know which model ultimately served the request.

```python
from langchain.chat_models import init_chat_model

class ModelRegistry:
    def __init__(self, model_ids: list[str]):
        self.models = [init_chat_model(m) for m in model_ids]

    def invoke(self, messages, **kwargs):
        for i, model in enumerate(self.models):
            try:
                return model.invoke(messages, **kwargs)
            except Exception:
                if i == len(self.models) - 1:
                    raise

registry = ModelRegistry([
    "claude-sonnet-4-5-20250929",  # primary
    "openai:gpt-4o",               # fallback
    "openai:gpt-4o-mini",          # cheap fallback
])
```

**When to use:** Any production agent that can't afford downtime from a single provider outage.

### Retry with Exponential Backoff

Transient failures (rate limits, timeouts, 5xx errors) should be retried automatically:

| Parameter | Recommended Value | Why |
|---|---|---|
| **Max attempts** | 3 | Enough for transient issues, fast enough to fail on real outages |
| **Wait strategy** | Exponential backoff, 2–10 seconds | Avoids thundering herd on rate limits |
| **Retry on** | Rate limit errors, timeouts, server errors (5xx) | These are transient by nature |
| **Don't retry on** | Auth errors (401/403), bad request (400), content policy (4xx) | These won't resolve on retry |

**Combined pattern:** Wrap each model call with retry logic. Wrap the retry-enabled call with the fallback loop. This gives you retry-per-model + fallback-across-models.

### Database Connection Pooling

For agents with persistence (checkpointing, memory, sessions), configure connection pooling:

| Parameter | Recommended Value | Sizing Rule |
|---|---|---|
| **Pool size** | 20 | Expected concurrent agent sessions |
| **Max overflow** | 10 | 50% of pool size for burst handling |
| **Pool timeout** | 30 seconds | How long to wait for a connection before erroring |
| **Connection recycle** | 1800 seconds (30 min) | Prevents stale connections from accumulating |
| **Pre-ping** | Enabled | Validates connections before use, avoids stale connection errors |

### Graceful Degradation

Production agents should degrade gracefully, not crash:

| Component Failure | Degradation Strategy |
|---|---|
| **Primary LLM down** | Fall back to secondary model |
| **Database unreachable** | Serve stateless responses, queue state updates for retry |
| **Memory/vector store down** | Continue without long-term memory, log the gap |
| **Tracing/observability down** | Continue serving, buffer telemetry locally |
| **Rate limit hit** | Queue requests, return estimated wait time |

---

## Production Failure Modes

For pattern-level failure modes (infinite loops, context explosion, cascade errors, etc.), see the Failure Mode Catalogue in `patterns.md`. The following are organizational/process failure modes specific to production deployments:

| Failure | Description | Mitigation |
|---|---|---|
| **Agent-Washing** | Renaming RPA as "agent." System can't handle unseen cases. | Validate with novel inputs, not just happy paths. |
| **Workflow Transplant** | Inserting agent into existing process without redesign. | Redesign the workflow first, then build the agent. |
| **Launch and Leave** | No ongoing evaluation. Performance degrades silently. | Continuous eval pipeline, learning loop. |
| **No Cost Model** | Token costs at scale surprise the org. | Model costs before building. Include in business case. |
| **Wrong Pattern Selection** | Using Hierarchical when Sequential suffices. | Follow the pattern selection decision framework. |
| **Rate Limit Cascade** | Parallel agents exhaust provider rate limits. | Concurrency caps, retry with backoff. |

---

## Deployment Checklist

### Before Production

- [ ] Workflow mapped end-to-end before building
- [ ] Technology selection hierarchy applied (is an agent actually needed?)
- [ ] Pattern selection justified (topology + behavioral + data flow)
- [ ] Cost model computed at expected scale
- [ ] Evaluation dataset built from real/representative user interactions
- [ ] Human approval gates at all high-risk decision points
- [ ] Context budget defined and enforced
- [ ] Tool count minimized (questioned every tool's necessity)
- [ ] Error handling at every node (tool failures, model failures, timeout)
- [ ] Max iteration caps on all loops
- [ ] Concurrency caps on all parallel fan-outs

### At Production

- [ ] End-to-end tracing enabled (LangSmith or equivalent)
- [ ] Structured logging with thread_id, node, latency, tokens, errors
- [ ] Cost tracking per invocation
- [ ] Alerting on error rate, latency, token cost anomalies
- [ ] Shadow mode or canary deployment before full rollout
- [ ] Learning loop: corrections logged, categorized, fed back
- [ ] Checkpointing enabled with appropriate backend (Postgres for production)
- [ ] Rate limiting on external tool calls
- [ ] PII detection/redaction if handling user data
- [ ] Rollback plan if agent performance degrades

### Ongoing

- [ ] Regular evaluation against current data (not stale test sets)
- [ ] Tool design review every major model update
- [ ] Cost review monthly
- [ ] Human override rate trending downward
- [ ] Prompt/knowledge base refinement from learning loop
