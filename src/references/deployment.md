# Deployment Reference

Patterns for serving agents as APIs, containerizing them, and standing up a monitoring stack. Complements `production.md` (which covers what to build) with how to deploy it.

## Table of Contents

1. [API Serving](#api-serving)
2. [Streaming](#streaming)
3. [Health Checks](#health-checks)
4. [Middleware Stack](#middleware-stack)
5. [Environment Configuration](#environment-configuration)
6. [Containerization](#containerization)
7. [Monitoring Stack](#monitoring-stack)
8. [Long-Term Memory](#long-term-memory)

---

## API Serving

### Architecture

An agent service is an async web server wrapping a compiled graph. The server manages:
- **Lifespan:** Initialize expensive resources (graph compilation, DB connections, tracing) at startup, clean up at shutdown. Never re-compile per request.
- **Request validation:** Validate all incoming data with schemas before it reaches the agent.
- **Error handling:** Global exception handler catches unhandled errors. Never expose stack traces to clients.

### Key Design Decisions

| Decision | Recommendation | Why |
|---|---|---|
| **Framework** | Async-first (FastAPI, Starlette, etc.) | Agent workloads are I/O-bound (LLM calls, tool calls, DB) |
| **ASGI server** | uvicorn with uvloop | Best async I/O performance |
| **Workers** | 2× CPU cores | I/O-bound workloads benefit from more workers than CPU-bound |
| **Request validation** | Schema validation on every endpoint | Catches bad input before it hits the agent |
| **CORS** | Explicit origin allowlist | Never use `*` in production |
| **Secrets** | Environment variables only | Never hardcode, never commit to version control |

### Endpoint Design

| Endpoint | Method | Purpose |
|---|---|---|
| `/chat` | POST | Synchronous agent invocation — send message, receive complete response |
| `/chat/stream` | POST | Streaming agent invocation — SSE for real-time token delivery |
| `/health` | GET | Dependency health checks for load balancers and orchestrators |
| `/metrics` | GET | Prometheus-compatible metrics endpoint |

---

## Streaming

For agents that need to deliver tokens in real-time (chat UIs, voice applications), use Server-Sent Events (SSE).

### Stream Modes

| Mode | What It Returns | Best For |
|---|---|---|
| **Messages** | Token-level chunks as they're generated | Chat UIs — lowest latency to first token |
| **Values** | Full state snapshot after each graph node completes | Dashboards — see the full picture at each step |
| **Updates** | State diff per node (only what changed) | Debugging — minimal data, shows exactly what each node did |

### Design Considerations

- Use SSE (`text/event-stream`) over WebSockets for agent streaming — simpler, HTTP-native, sufficient for server-to-client
- Send a `[DONE]` sentinel event so clients know the stream has ended
- Set appropriate timeouts — agent streams can last 30–60 seconds for complex workflows
- Buffer streaming responses behind a reverse proxy (nginx, Caddy) with `X-Accel-Buffering: no`

---

## Health Checks

Every agent service needs a health endpoint that load balancers and orchestrators can poll.

### What to Check

| Dependency | Check | Include? |
|---|---|---|
| **Database** | Execute a trivial query (`SELECT 1`) | Always — agents with persistence fail silently without DB |
| **Cache/Redis** | Ping | If used for rate limiting or session storage |
| **LLM provider** | Reachability | Optional — adds latency, and provider status is external |
| **Vector store** | Connectivity | If memory/RAG is critical to functionality |

### Rules

- Health endpoints must respond in **<500ms**. Don't include checks that might be slow.
- Return structured JSON: `{"status": "healthy|degraded|unhealthy", "checks": {...}}`
- **Healthy:** All critical dependencies up. **Degraded:** Non-critical dependency down, still functional. **Unhealthy:** Critical dependency down, can't serve requests.
- Don't check LLM providers on every health poll — they're external and slow. Check them separately on a longer interval.

---

## Middleware Stack

Middleware wraps every request. Order matters — outermost runs first.

### Recommended Order

| Order | Middleware | Purpose |
|---|---|---|
| 1 | **Logging context** | Binds request metadata (request ID, user ID, path) to all downstream log entries |
| 2 | **Metrics** | Records request count and duration for Prometheus |
| 3 | **CORS** | Handles preflight and cross-origin headers |
| 4 | **Rate limiting** | Applied per-endpoint — rejects requests exceeding limits |

### Logging Context Middleware

Bind request-scoped metadata at the start of each request so every log entry within that request automatically includes `request_id`, `user_id`, `method`, and `path`. Clear the context after the request completes. This eliminates manual context threading.

### Metrics Middleware

Record two things per request:
1. **Counter:** Increment by method, path, and status code → `http_requests_total`
2. **Histogram:** Observe request duration by method and path → `http_request_duration_seconds`

These feed directly into Prometheus/Grafana dashboards.

---

## Environment Configuration

Manage settings across dev/staging/production without code changes.

### Configuration Categories

| Category | Settings |
|---|---|
| **App** | Environment name, debug flag, API prefix |
| **LLM** | Primary model, fallback model, temperature |
| **Database** | Connection URL, pool size, max overflow |
| **Auth** | JWT secret, token expiry |
| **Rate limiting** | Default limits, per-endpoint overrides |
| **Observability** | Log level, log format, tracing enabled, tracing provider |

### Principles

1. **Single source:** Load from `.env` file, override with environment variables
2. **Environment-specific defaults:** Dev/test auto-enables debug, sets log level to DEBUG, uses console log format, relaxes rate limits
3. **Parse once:** Cache settings at startup — don't re-parse on every request
4. **Never hardcode secrets:** API keys, JWT secrets, DB passwords always come from environment variables
5. **Validate at startup:** Fail fast if required settings (API keys, DB URL) are missing

### Environment Overrides

| Setting | Development | Production |
|---|---|---|
| Debug | `true` | `false` |
| Log level | `DEBUG` | `WARNING` |
| Log format | Console (human-readable) | JSON (machine-parseable) |
| Rate limits | Relaxed (1000/day) | Strict (200/day, 50/hour) |
| Tracing | Optional | Required |

---

## Containerization

### Architecture

A production agent deployment has three layers:

| Layer | Components | Purpose |
|---|---|---|
| **Application** | Agent service (ASGI server + compiled graph) | Serves agent API |
| **Data** | PostgreSQL + pgvector | Checkpointing, sessions, vector memory |
| **Monitoring** | Prometheus + Grafana | Metrics collection and visualization |

### Container Design Principles

| Principle | Recommendation |
|---|---|
| **Base image** | Slim Python image (3.12-slim or equivalent) — small, secure |
| **Dependency caching** | Install dependencies in a separate layer before copying application code — Docker cache speeds rebuilds |
| **Database** | PostgreSQL with pgvector extension — covers checkpointing, sessions, and vector similarity search in one service |
| **Health checks** | Always define in orchestration config — prevents startup race conditions between app and database |
| **Volumes** | Named volumes for database data — never bind-mount DB data directories in production |
| **Secrets** | Pass via environment variables or secrets manager — never bake into images |
| **Restart policy** | `unless-stopped` for the agent service — auto-recover from transient failures |
| **Dependency ordering** | Agent service starts only after database passes health check |

### Minimal Service Composition

| Service | Image | Ports | Depends On |
|---|---|---|---|
| **App** | Custom build | 8000 | DB (healthy) |
| **Database** | pgvector/pgvector:pg16 | 5432 | — |
| **Prometheus** | prom/prometheus | 9090 | App |
| **Grafana** | grafana/grafana | 3000 | Prometheus |

---

## Monitoring Stack

### Components

| Component | Role | Scrape Interval |
|---|---|---|
| **Prometheus** | Collects metrics from the `/metrics` endpoint on the agent service | 15 seconds |
| **Grafana** | Visualizes metrics, hosts dashboards, sends alerts | — |
| **cAdvisor** (optional) | Container-level CPU, memory, network metrics | 15 seconds |

### Recommended Dashboards

| Dashboard | Key Panels | Alert On |
|---|---|---|
| **Agent Performance** | LLM inference latency (p50/p95/p99), requests/sec, error rate by endpoint | p95 latency > 5s, error rate > 5% |
| **Cost Tracking** | Tokens per request, cost per request, daily spend trend | Daily spend > 2× rolling average |
| **Infrastructure** | DB connection pool usage, container CPU/memory, request queue depth | Pool exhaustion (>90%), OOM events |

### Metrics to Expose

See the Metrics for Agents table in `production.md` for the full metric definitions. At minimum:

| Metric | Type | Why |
|---|---|---|
| `http_requests_total` | Counter | Traffic volume and error rate |
| `http_request_duration_seconds` | Histogram | Latency distribution |
| `llm_inference_duration_seconds` | Histogram | Model performance tracking |
| `llm_tokens_total` | Counter | Cost tracking |
| `db_connections_active` | Gauge | Connection pool health |
| `agent_task_completion_total` | Counter | Agent reliability |

---

## Long-Term Memory

For agents that need to remember across sessions — user preferences, learned facts, prior interaction patterns.

### Memory Types

| Memory Type | Scope | Persistence | Use Case |
|---|---|---|---|
| **Conversation (short-term)** | Per thread | Session duration | Multi-turn chat, context within a single session |
| **Cross-session (long-term)** | Per user | Permanent | User preferences, learned facts, prior interaction history |
| **Semantic (vector)** | Global | Permanent | RAG, knowledge retrieval, similar-case lookup |
| **Structured (relational)** | Global | Permanent | User profiles, transaction history, audit logs |

### Implementation Approaches

| Approach | Best For | Trade-off |
|---|---|---|
| **Graph checkpointer** (built-in) | Conversation memory within sessions | Simple, but limited to per-thread state |
| **Graph store** (built-in) | Cross-session key-value memory | Persists across sessions, but no semantic search |
| **Vector store** (pgvector, Pinecone, etc.) | Semantic memory — retrieve by meaning, not key | Requires embeddings, more infrastructure |
| **Dedicated memory service** (mem0, Zep, etc.) | Full memory lifecycle — auto-extract, store, retrieve, forget | Higher-level abstraction, external dependency |

### Design Principles

1. **Separate conversation state from long-term memory.** Conversation state (checkpointer) is scoped to a thread. Long-term memory (store or vector DB) is scoped to a user and persists across threads.
2. **Retrieve before invoking.** Before each agent invocation, search long-term memory for context relevant to the current query. Inject as system context, not conversation history.
3. **Store asynchronously.** Don't block the response to persist memories. Fire-and-forget after the response is sent.
4. **Scope memory to users.** Always key memory by user ID. Never cross-contaminate between users.
5. **Use one database.** PostgreSQL + pgvector can serve as checkpointer storage, relational store, and vector store — reducing infrastructure complexity.

For retrieval pipeline patterns over vector stores — hybrid search, reranking, chunking strategies, and agentic RAG architectures — see `retrieval.md`.
