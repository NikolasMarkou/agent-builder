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

### Minimal FastAPI Skeleton

```python
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from langchain.agents import create_agent
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

graph = None
checkpointer = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global graph, checkpointer
    checkpointer = AsyncPostgresSaver.from_conn_string(os.environ["DATABASE_URL"])
    await checkpointer.setup()
    graph = create_agent(
        model="claude-sonnet-4-5-20250929",
        tools=[...],  # your tools here
        checkpointer=checkpointer,
    )
    yield
    # cleanup resources

app = FastAPI(title="Agent Service", lifespan=lifespan)

class ChatRequest(BaseModel):
    message: str
    thread_id: str

class ChatResponse(BaseModel):
    response: str
    thread_id: str

@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    try:
        result = await graph.ainvoke(
            {"messages": [{"role": "user", "content": req.message}]},
            config={"configurable": {"thread_id": req.thread_id}},
        )
        return ChatResponse(
            response=result["messages"][-1].content,
            thread_id=req.thread_id,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail="Agent invocation failed")
```

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

### SSE Streaming Endpoint

```python
import json
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

class StreamRequest(BaseModel):
    message: str
    thread_id: str

@app.post("/chat/stream")
async def chat_stream(req: StreamRequest):
    async def event_generator():
        async for event, chunk in graph.astream(
            {"messages": [{"role": "user", "content": req.message}]},
            config={"configurable": {"thread_id": req.thread_id}},
            stream_mode="messages",
        ):
            if hasattr(chunk, "content") and chunk.content:
                data = json.dumps({"content": chunk.content, "type": event})
                yield f"data: {data}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"X-Accel-Buffering": "no", "Cache-Control": "no-cache"},
    )
```

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

### Health Check Endpoint

```python
import asyncio
from fastapi import FastAPI
from fastapi.responses import JSONResponse

@app.get("/health")
async def health():
    checks = {}
    status = "healthy"

    # Database check
    try:
        async with checkpointer._pool.connection() as conn:
            await conn.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception:
        checks["database"] = "failed"
        status = "unhealthy"

    # Optional: vector store check
    # try:
    #     await vector_store.ping()
    #     checks["vector_store"] = "ok"
    # except Exception:
    #     checks["vector_store"] = "failed"
    #     status = "degraded"

    code = 200 if status == "healthy" else 503
    return JSONResponse(
        status_code=code,
        content={"status": status, "checks": checks},
    )
```

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

### Dockerfile

```dockerfile
FROM python:3.12-slim AS base

WORKDIR /app

# Dependency layer (cached unless requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application layer
COPY . .

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4", "--loop", "uvloop"]
```

### docker-compose.yml

```yaml
services:
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://agent:${POSTGRES_PASSWORD}@db:5432/agent
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: agent
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: agent
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U agent"]
      interval: 5s
      timeout: 5s
      retries: 5

  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    depends_on:
      - app

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

volumes:
  pgdata:
```

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

### Prometheus Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "agent-service"
    static_configs:
      - targets: ["app:8000"]
```

### Metrics Exposition

```python
from prometheus_client import Counter, Histogram, Gauge, make_asgi_app

REQUEST_COUNT = Counter("http_requests_total", "Total requests", ["method", "path", "status"])
REQUEST_DURATION = Histogram("http_request_duration_seconds", "Request duration", ["method", "path"])
LLM_DURATION = Histogram("llm_inference_duration_seconds", "LLM call duration", ["model"])
LLM_TOKENS = Counter("llm_tokens_total", "Tokens consumed", ["model", "direction"])
DB_CONNECTIONS = Gauge("db_connections_active", "Active DB connections")

# Mount metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)
```

### Recommended Dashboards

| Dashboard | Key Panels | Alert On |
|---|---|---|
| **Agent Performance** | LLM inference latency (p50/p95/p99), requests/sec, error rate by endpoint | p95 latency > 5s, error rate > 5% |
| **Cost Tracking** | Tokens per request, cost per request, daily spend trend | Daily spend > 2× rolling average |
| **Infrastructure** | DB connection pool usage, container CPU/memory, request queue depth | Pool exhaustion (>90%), OOM events |

### Metrics to Expose

See the Metrics for Agents table in `production.md` for the full metric definitions and labels.

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

### Memory Implementation

```python
from langgraph.store.memory import InMemoryStore
from langgraph.store.postgres import PostgresStore

# Development: in-memory store
store = InMemoryStore()

# Production: persistent store
store = PostgresStore.from_conn_string(os.environ["DATABASE_URL"])

# Store a user preference
await store.aput(("user", user_id, "preferences"), "theme", {"value": "dark"})

# Retrieve before invocation
prefs = await store.aget(("user", user_id, "preferences"), "theme")

# Wire store into agent
agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[...],
    store=store,
    checkpointer=checkpointer,  # separate: conversation state
)
```

### Design Principles

1. **Separate conversation state from long-term memory.** Conversation state (checkpointer) is scoped to a thread. Long-term memory (store or vector DB) is scoped to a user and persists across threads.
2. **Retrieve before invoking.** Before each agent invocation, search long-term memory for context relevant to the current query. Inject as system context, not conversation history.
3. **Store asynchronously.** Don't block the response to persist memories. Fire-and-forget after the response is sent.
4. **Scope memory to users.** Always key memory by user ID. Never cross-contaminate between users.
5. **Use one database.** PostgreSQL + pgvector can serve as checkpointer storage, relational store, and vector store — reducing infrastructure complexity.

For retrieval pipeline patterns over vector stores — hybrid search, reranking, chunking strategies, and agentic RAG architectures — see `retrieval.md`.

---

## Failure Modes

| Failure | Cause | Mitigation |
|---|---|---|
| **Silent health check pass** | Health endpoint returns 200 but agent can't reach LLM | Include LLM connectivity in health check (with timeout + caching) |
| **Container OOM** | Agent context grows unbounded in memory | Set container memory limits, use SummarizationMiddleware, stream responses |
| **Stale connections** | DB pool hands out dead connections after idle period | Enable pre-ping, set connection recycle interval |
| **SSE disconnect** | Client drops mid-stream, server keeps generating | Set response timeouts, handle `GeneratorExit` in stream generator |
| **Config drift** | Env vars differ between staging and production | Validate all required settings at startup, fail fast on missing values |
| **Memory cross-contamination** | Long-term memory not keyed by user ID | Always scope store operations to user namespace |
