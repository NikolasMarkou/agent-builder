<!-- benchmarks-as-of: 2026-06 -->
# Text Retrieval for Agentic AI

Production retrieval patterns for agents that need to search, rank, and synthesize from knowledge bases. Covers sparse retrieval (BM25), dense retrieval (bi-encoders), hybrid fusion, reranking, query transformation, corrective loops, GraphRAG, and agentic RAG architectures.

**When to use this reference:** The agent retrieves and synthesizes from a document corpus, knowledge base, or unstructured data store. This is NOT for code search or structured data filtering — use `text-tools.md` for those (three-layer search stack: ripgrep → ast-grep → semantic tools).

> **Design axiom: Tiered escalation.** The same principle from `text-tools.md` applies here. Cheap sparse retrieval first, dense only when needed, reranking only when precision matters, agentic loops only for complex multi-hop queries. Each tier up costs more but handles harder queries.

**Install:**
```bash
pip install langchain langgraph
```

## Table of Contents

1. [When RAG vs. When Not](#when-rag-vs-when-not)
2. [Local RAG vs Global RAG](#local-rag-vs-global-rag)
3. [The Retrieval Stack](#the-retrieval-stack)
4. [Sparse Retrieval](#sparse-retrieval)
5. [Dense Retrieval](#dense-retrieval)
6. [Late Interaction and Cross-Encoders](#late-interaction-and-cross-encoders)
7. [Hybrid Search](#hybrid-search)
8. [Pre-Retrieval: Query Transformation](#pre-retrieval-query-transformation)
9. [Post-Retrieval: Corrective Loops](#post-retrieval-corrective-loops)
10. [GraphRAG and Multi-Hop Retrieval](#graphrag-and-multi-hop-retrieval)
11. [Agentic RAG Architectures](#agentic-rag-architectures)
12. [Chunking Strategies](#chunking-strategies)
13. [Production Tooling](#production-tooling)
14. [Retrieval Evaluation](#retrieval-evaluation)
15. [Decision Framework](#decision-framework)
16. [Failure Modes](#failure-modes)

---

## When RAG vs. When Not

Before building a retrieval pipeline, determine whether you actually need one.

| Scenario | Recommendation |
|---|---|
| Corpus fits in context window (<100K tokens) | Skip RAG. Load directly. Cheaper, simpler, higher recall. |
| Corpus is a codebase | Use `text-tools.md` (ripgrep + ast-grep + semantic tools). Just-in-time context, not pre-indexed RAG. |
| Corpus too large for context but greppable; exact terms / multi-hop constraints dominate; or it changes daily | Direct Corpus Interaction (DCI) — agentic grep, no index. See `direct-corpus-interaction.md`. |
| Corpus is structured data (tables, JSON, SQL) | Use `tabular-data.md` or `text-tools.md` (jq, sqlite3). |
| Corpus is large, unstructured, and changes infrequently | RAG with pre-indexed embeddings. This reference applies. |
| Corpus is large and changes frequently | RAG with incremental indexing + staleness monitoring. |
| Agent needs to reason across entity relationships | GraphRAG or agentic sub-query decomposition. |
| Queries are keyword-heavy (IDs, codes, exact terms) | BM25 must be in the stack. Dense-only will fail. |

> **Design axiom: Model costs first.** RAG adds embedding cost (one-time indexing + per-query encode), vector DB infrastructure, and reranking latency. Calculate whether the cost is justified vs. simply using a larger context window or fine-tuning.

---

## Local RAG vs Global RAG

Before selecting methods, classify the *question shape*. This is the organizing distinction behind every technique in this reference.

**Local questions** are answerable from a few chunks or documents — "When was X founded?", "What does clause 7 of this contract say?". Critically, this includes multi-hop questions: connecting a handful of documents to chain evidence (HotpotQA, 2WikiMultiHopQA) is still *local*. Top-k retrieval is the right tool — the answer lives in a bounded, locatable set of passages.

**Global questions** require aggregating across the *entire* corpus — "What are the main themes?", "Which are the top 10 most-cited papers?", "How many filings mention sanctions?". Counting, sorting, extremum, and top-k-over-everything are all global: no fixed set of k chunks contains the answer, because the answer is a property of the whole collection.

**Dense retrieval fails catastrophically on global queries.** A dense retriever ranks all documents by similarity and returns only the top k — but a global answer needs information scattered across *all* of them. On the GlobalQA benchmark, the strongest naive retrieval baseline scored only **1.51 F1** (Luo & Li et al. 2025). Three causes are diagnosed:

1. **Fixed-granularity chunking disrupts document integrity.** Splitting at arbitrary token boundaries separates an entity from its attributes, producing double-counting or omissions when the agent tries to aggregate.
2. **Dense retrieval returns relevant-but-not-useful noise.** Semantically similar passages crowd out the factually required ones and consume the context window, so the genuinely needed evidence never reaches the generator.
3. **LLMs are poor at numerical computation.** Even handed every relevant fact, models count, compare, and rank unreliably — global answers demand exactly these operations.

**This framing organizes the methods that follow.** Metadata filtering and self-query sharpen *local* precision by narrowing the candidate set before retrieval. Dual-store routing delegates exact aggregation to SQL, sidestepping cause (3) entirely. Graph RAG and RAPTOR pre-compute corpus-level structure (community summaries, hierarchical trees) so *global* sensemaking reads from a prepared index rather than re-aggregating at query time. See `multi-hop-rag.md`, which names GraphRAG's local-search and global-search modes explicitly.

---

## The Retrieval Stack

Production retrieval is layered, not monolithic. Each layer adds cost but handles harder queries.

```
AGENTIC CONTROLLER (LLM)
  decides: retrieve? from where? rewrite query? enough context?
    │
    ▼
PRE-RETRIEVAL ── HyDE, query expansion, sub-query decomposition
    │
    ▼
FIRST-STAGE ──── Sparse (BM25/SPLADE) + Dense (bi-encoder) + Graph
  RETRIEVAL       Fusion: RRF / DBSF / convex combination
    │
    ▼
SECOND-STAGE ─── Reranking: cross-encoder, ColBERT, LLM reranker
    │
    ▼
POST-RETRIEVAL ─ CRAG confidence gating, Self-RAG critique, context compression
    │
    ▼
GENERATION ───── LLM + grounded context
```

Not every query needs every layer. Simple factoid queries skip pre-retrieval and post-retrieval. Complex multi-hop queries use the full stack. Adaptive routing by query complexity cuts cost 40-60%.

---

## Sparse Retrieval

### BM25

The workhorse. Published in the 1990s, BM25 remains the de facto first-stage sparse retriever in production RAG as of 2026. A 2025 benchmark on scientific literature (1,200 queries, 200K paper corpus) found BM25 outperforms neural retrievers by ~30% on keyword-oriented sub-queries that agents tend to generate.

**When to use:** Exact identifiers (error codes, part numbers, legal citations). Technical terminology with no semantic neighbors. Short keyword-heavy queries typical of agent tool calls. Corpora where domain vocabulary diverges from embedding model training data.

**When NOT to use:** Semantic paraphrase queries ("best pizza spot" vs. "acclaimed pizzeria"). Zero-shot domains with novel vocabulary. Conceptual/thematic queries ("what are the main risks?").

**Key tuning:**
- `k1 = 1.2` (conservative, faster saturation) vs `k1 = 2.0` (better for long docs)
- `b = 0.75` universal default; lower for very short documents
- Preprocessing matters at scale: lowercase, stopword removal, stemming/lemmatization

**Production implementations:** Elasticsearch/OpenSearch (BM25 default since ES 5.0), `pg_textsearch` (Postgres, true BM25 with WAND optimization), Qdrant sparse embeddings, Redis 8.4 `FT.HYBRID`, `rank_bm25` (Python).

### SPLADE (Learned Sparse Retrieval)

Uses a BERT-based encoder to produce sparse vectors with learned query/document expansion — "acetaminophen" also activates "pain reliever" in document representations. Outperforms BM25 on semantic-heavy queries while maintaining sparse vector efficiency.

**When to use:** Natural language corpora where vocabulary gap is a problem and you have the inference budget.

**When NOT to use:** Exact numeric/code/identifier queries (SPLADE's expansion adds noise). Latency-critical paths. No GPU for inference.

---

## Dense Retrieval

Bi-encoders encode queries and documents independently, then retrieve via approximate nearest-neighbor (ANN) search.

**Current production models (2025-2026):**

| Model | Dims | Notes |
|---|---|---|
| `BAAI/bge-large-en-v1.5` | 1024 | Strong general-purpose open-source |
| `intfloat/e5-mistral-7b-instruct` | 4096 | Best open MTEB scores; high cost |
| `text-embedding-3-large` (OpenAI) | 3072 | Strong; proprietary, API latency |
| `Cohere embed-v3` | 1024 | Best managed option with native int8 |
| `BGE-M3` | 1024 | Multi-lingual, multi-granularity |

**Implementation notes:**
- Use mean pooling + L2 normalization with retrieval-tuned checkpoints (NOT `[CLS]` pooler output from generic LMs)
- ANN indexes: HNSW (Qdrant, Weaviate) or FAISS; tune `efSearch` and `m` to latency budget
- P50 targets: encode ≤15ms (fp16, batch ≥16), ANN search ≤15-25ms (HNSW efSearch=64)

**When to use:** Semantic similarity queries, paraphrase matching, thematic retrieval.

**When NOT to use:** Exact numeric/identifier matching. Rare proper nouns not in training data. Out-of-domain corpora with poor embedding coverage.

**Key insight:** Fine-tuned embeddings on your specific corpus shrink the BM25 advantage. Domain-fine-tuned dense models on keyword-heavy corpora can match hybrid performance — but fine-tuning requires labeled data and effort. For detailed guidance on selecting, evaluating, and benchmarking embedding models, see `embeddings.md`.

---

## Late Interaction and Cross-Encoders

### ColBERT (Late Interaction)

Retains per-token embeddings (unlike bi-encoder single-vector pooling). Scores via MaxSim: for each query token, find the maximum dot product across all document tokens, then sum. Cross-encoder-class accuracy at bi-encoder-class latency for reranking.

**Model:** `colbert-ir/colbertv2.0` (HuggingFace, integrated into Qdrant FastEmbed).

**Best used as:** Second-stage reranker. Store document token embeddings offline; only query encoding at runtime.

### Cross-Encoders

Jointly encode query + candidate through full cross-attention. Most accurate rerankers, but cannot be precomputed — viable only over small candidate sets (top 30-100 from first-stage).

**Models:** `cross-encoder/ms-marco-MiniLM-L-6-v2` (fast), `cross-encoder/ms-marco-electra-base` (stronger), Cohere Rerank API, Jina Reranker.

**Latency:** ≤40-80ms for batch of 16 candidates (maxlen=512). Budget carefully in agentic loops with multiple retrieval calls per step.

**When to use reranking:** Precision at top-1 is critical (single-answer systems). Reranking gives the highest single-change precision gain — consistently outperforms any individual retrieval method change.

**When NOT to use reranking:** Top-5 to LLM is sufficient (LLM can handle some noise). Latency budget is tight and retrieval is called many times per step.

---

## Hybrid Search

The canonical production pattern: sparse + dense in parallel, fused via RRF.

### Reciprocal Rank Fusion (RRF)

```
RRF(d) = Σ 1/(k + rank_l(d))   for each retrieval list l
```

Where `k ≈ 60` prevents top-1 documents from dominating. RRF is scale-invariant — no need to normalize BM25 scores (0–∞) against dense cosine scores (0–1).

**Why RRF is the default:** Zero labeled data required. Robust. `k=60` is the universally recommended starting point. Tune only when you have ≥50 labeled query pairs.

**Failure mode:** RRF discards score magnitude. A cosine similarity of 0.99 and 0.51 get treated identically if both rank #1. Use convex combination when score magnitude matters and you have labeled data.

### Convex Combination (Score-Weighted)

```
score(d) = α · dense(d) + (1-α) · sparse(d)
```

Requires normalizing scores (z-score or min-max) before combining. Typical tuned values: `α ≈ 0.7` (semantic corpora), `α ≈ 0.3` (technical corpora). A misconfigured convex combination can perform worse than dense-only — start with RRF.

### DBSF (Distribution-Based Score Fusion)

Qdrant's approach. Uses distributional statistics (mean, std) to normalize before fusion. More principled than min-max; handles outlier scores from sparse systems.

### Production Hybrid Pipeline

```python
from langchain.tools import tool

@tool
def hybrid_retrieve(query: str, k: int = 5) -> list[dict]:
    """Retrieve documents using hybrid sparse+dense search with reranking."""
    # First stage: parallel retrieval
    dense_candidates = dense_index.search(embed(query), k=100)
    sparse_candidates = bm25_index.search(tokenize(query), k=100)

    # Score fusion (RRF, k=60)
    fused = rrf_merge([dense_candidates, sparse_candidates], k=60)

    # Second stage: reranking
    reranked = cross_encoder.rerank(query, fused[:50])

    return reranked[:k]
```

**Latency budget per retrieval call:**

| Stage | P50 Target |
|---|---|
| Query encode | ≤15ms |
| ANN search | ≤25ms |
| Rerank (batch 16) | ≤80ms |
| **Total first-call** | **~120ms** |
| Cached repeat | ~30ms |

**Caching:** Key embedding cache by `SHA-256(text)`. Key query-to-neighbor cache by embedding (reuse if cosine similarity >0.95, TTL minutes).

---

## Pre-Retrieval: Query Transformation

### HyDE (Hypothetical Document Embeddings)

Generate a hypothetical answer using the LLM, embed that answer, search for real documents similar to the hypothesis. Maps the short, sparse query into the rich representation space of documents.

**When to use:** Abstract, underspecified, or natural-language-heavy queries. Zero-shot scenarios. Legal/medical corpora where phrasing diverges significantly from queries.

**When NOT to use:** Keyword-heavy queries where BM25 already excels. High-throughput paths where the LLM generation adds unacceptable latency.

**Key risk:** If the LLM hallucinates a confidently wrong hypothesis, retrieval will be confidently wrong. Always combine with BM25 as grounding fallback.

**Variant — Multi-HyDE:** Generate 3-5 non-equivalent hypothetical documents, embed and search with each, aggregate before fusion. Demonstrated 11.2% accuracy improvement over single HyDE in financial RAG.

### Query Decomposition

For complex multi-hop questions, decompose into sub-queries, retrieve independently, then synthesize. The A-RAG framework exposes keyword, semantic, and chunk-level retrieval tools directly to the agent.

```python
# Agent decomposes: "How does Company X's exposure to Y's supply chain affect risk?"
sub_queries = [
    "Company X supplier relationships",
    "Company Y supply chain partners",
    "Financial exposure metrics between companies"
]
# Retrieve independently, aggregate with provenance tracking
results = [hybrid_retrieve(sq) for sq in sub_queries]
```

### Query Expansion

Add synonyms, related terms, or LLM-generated variants before retrieval. Simpler and cheaper than HyDE. Meaningful recall improvement for niche corpora where the embedding model lacks domain coverage.

### Metadata Filtering (Pre-Retrieval Gate)

Metadata filtering is a **pre-retrieval gate, not a search method**. Each chunk stores a dense embedding *and* a structured metadata payload — source ID, section, page, author, date, category, numeric attributes. At query time you constrain the ANN search to points whose metadata satisfies stated conditions (e.g., `category = "news" AND date > 2024-01-01`). This is the foundation of multi-tenant, faceted, and time-scoped retrieval, and is the cheapest way to improve local precision: it shrinks the candidate set to the rows that are *eligible* before semantic ranking even runs.

**Keep metadata separate from the embedding.** Do NOT serialize structured fields into the chunk text before embedding. Doing so dilutes the semantic vector into a noisy "semantic average," and you *still* cannot do exact range filtering (`year > 2020`) on a blurred vector. A separate structured field preserves a clean vector AND enables exact boolean / range / set operations the embedding space cannot express.

**Pre-filter vs. post-filter trade-off:**

| Strategy | How it works | Guarantee | Cost |
|----------|--------------|-----------|------|
| **Pre-filter** | Filter first, then search within the eligible subset | Returns k results that all satisfy the filter | Hard to do efficiently on graph ANN indexes — an HNSW graph is built over the whole dataset, so an arbitrary filtered subset disrupts traversal; very low cardinality can disconnect the graph |
| **Post-filter** | Search first, then drop results that fail the filter | Works on any index, trivially simple | May return far fewer than k (or zero) on selective filters; mitigate by over-fetching (large `top_k`) |

Many systems combine both, and some vector DBs add filterable-index links so filtered search stays efficient regardless of order.

**Works well:** low-cardinality categorical fields, date ranges, numeric attributes with exact comparators (eq / gt / lt / in). **Works poorly:** free-form text as metadata, very high-cardinality fields, anything needing fuzzy or semantic match (that belongs in the embedding).

**Schema-as-contract.** You can only filter on what you tagged at index time — changing the schema means re-indexing. Failure modes: schema gaps (a facet was never tagged), inconsistent tagging (`"Sci-Fi"` vs `"Science Fiction"`, or mismatched date formats that silently miss documents), and filter over-specificity (too many `AND`s or a low-cardinality field collapsing to a near-empty result set).

Hand-written filters are the manual baseline; **self-query** automates them by translating a natural-language query into this structured filter (covered next under Self-Query, below).

### Self-Query (Text-to-Filter)

A **self-querying retriever** uses an LLM to translate one natural-language query into a structured query with TWO parts: (a) a *semantic search string* used for similarity, and (b) a *filter expression* over metadata. "Horror movies made after 1980 with lots of explosions" becomes semantic string "lots of explosions" + filter `genre = Horror AND year > 1980`. It is the automation layer over the metadata filtering above — the user writes prose, the model emits the gate.

**How the translation is constrained.** The model is given (1) a description of what the documents contain, (2) the metadata field schema — field name, description, and type per field, (3) the ALLOWED comparators (`eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `nin`, `exists`) and boolean operators (`AND` / `OR` / `NOT`), and (4) a few-shot examples mapping example queries to their filters. A query that needs no filter must emit an explicit "no filter" signal. You MUST tell the model which comparators are allowed — otherwise it writes filters the store cannot execute.

**Why it beats plain semantic search.** Standard RAG embeds the whole query, blurring hard constraints ("after 1980", "directed by Nolan") into the vector where they cannot be enforced exactly. Self-query carves those constraints out into an exact filter and leaves only the genuinely semantic remainder ("lots of explosions") for vector matching — much higher precision on faceted queries.

**The schema is the contract.** The same metadata schema written at index time defines what can be filtered at query time. If the indexing schema and the query-time schema drift apart, retrieval silently breaks.

**Failure modes:** hallucinated filters (the model invents attributes or values not in the schema — the canonical failure; the store then errors or returns nothing); over-eager filtering or a wrong "no filter" decision on ambiguous queries; schema, syntax, or quoting errors the translator cannot parse; comparator/type mismatch (a numeric comparator on a string field, or a comparator the store does not support).

**Mitigation:** validate the generated filter against the schema BEFORE executing it; fall back to no-filter on any validation failure; constrain the model tightly with the full schema plus the allowed-comparator list plus 3-5 few-shot examples.

Self-query is the user-friendly face of metadata filtering, and it is also a building block of agentic routing — an agent can call self-query as a single tool, then choose among stores (see the Decision Framework and dual-store material later in this file).

---

## Post-Retrieval: Corrective Loops

> **Design axiom: Document failure modes.** Every retrieval call can return irrelevant results. Production systems need explicit confidence gating, not blind trust in retrieved context.

### Corrective RAG (CRAG)

A retrieval evaluator scores retrieved documents and triggers one of three actions:

| Confidence | Action | Latency Impact |
|---|---|---|
| **High** | Use retrieved context directly | None |
| **Medium** | Keep context AND add web search results | +200-500ms |
| **Low** | Discard, trigger alternative source or query rewrite | +300-800ms |

**Practical heuristic:** Use a confidence threshold on the dense cosine score of the top-1 result as a proxy CRAG evaluator before investing in a fine-tuned model.

### Self-RAG

The generator explicitly scores relevance and support before generating. In production without fine-tuning: approximate with structured prompting that asks the model to score `[IS_RELEVANT]`, `[IS_SUPPORTED]`, `[IS_USEFUL]` before generating the final response. Captures ~80% of the fine-tuned benefit.

### Adaptive RAG

Routes queries to different retrieval strategies based on complexity:

| Query Type | Strategy | Cost |
|---|---|---|
| Simple factoid | Skip retrieval or single-hop dense | Low |
| Moderate | Standard hybrid RAG | Medium |
| Complex multi-hop | Full agentic loop with decomposition | High |

Reduces cost 40-60% vs. running full agentic RAG on all queries.

---

## GraphRAG and Multi-Hop Retrieval

When queries require reasoning across multiple documents, entity-relationship traversal, or connecting 2-N evidence fragments, standard hybrid retrieval is insufficient. This section covers the basics; for the full multi-hop methodology taxonomy, decision matrix, implementation templates, and evaluation metrics, see `multi-hop-rag.md`.

### Quick Reference

| Method | Best For | Latency |
|---|---|---|
| Query Decomposition | Predictable hop structures | Medium |
| IRCoT (interleaved retrieval + CoT) | Variable-hop, dependent evidence chains | High |
| GraphRAG | Relational/entity reasoning | Medium-High |
| RAPTOR | Thematic/hierarchical documents | Low |
| CRAG Loop | High-stakes accuracy (layer on any method) | Medium |
| REAPER | Latency-critical production | Low (207ms) |
| Adaptive Routing | Mixed workloads, cost control | Variable |

### When to Use Multi-Hop

**When to use:** Queries require combining evidence from 2+ documents. Entity-relationship traversal ("indirect exposures of X to Y's suppliers"). Temporal or causal chain reasoning.

**When NOT to use:** Simple factoid queries (flat hybrid search is sufficient and faster). Corpus fits in context window (<100K tokens). No cross-document reasoning needed.

> **Design axiom: Tiered escalation.** Most queries are single-hop. Running full multi-hop on everything wastes 40-60% of compute. Use adaptive routing to classify query complexity and route accordingly. See `multi-hop-rag.md` §Adaptive Routing.

### GraphRAG Variants

| System | Mechanism | Trade-off |
|---|---|---|
| Microsoft GraphRAG | Entity graphs + Leiden community clustering + hierarchical summaries (Edge et al. 2024) | High construction cost; degrades above ~3M tokens; 5-20 point gain |
| LazyGraphRAG | Defers LLM-based community summarization to query time; only lightweight graph construction at index time (Microsoft 2024) | Indexing cost ≈ vector RAG (far below full GraphRAG); much lower query cost for global queries, tunable via a relevance budget. Microsoft reports ~700x lower query cost than full GraphRAG (directional) |
| HopRAG | Passage graph with pseudo-query edges; retrieve-reason-prune | Strong on logical relevance gaps |
| LightRAG / GLightRAG | Simplified KG structures | 10-50x lower construction cost; some accuracy loss |
| HippoRAG | Personalized PageRank over knowledge graphs | Memory-inspired; less production-proven |
| NodeRAG | Heterogeneous graph (entities, chunks, events, summaries as nodes) | Best indexing time and query efficiency |
| RAPTOR | Recursive tree of increasingly abstract summaries | Low latency; best for thematic/hierarchical docs |

For implementation templates (LangGraph IRCoT loop, query decomposition with parallel retrieval, multi-hop state shape), see `multi-hop-rag.md` §Implementation.

---

## Agentic RAG Architectures

The shift from static RAG to agentic RAG replaces "embed-search-generate" with a cyclic decision loop: the LLM plans, executes retrieval tools, evaluates results, and decides whether to re-retrieve or generate.

### Architecture Taxonomy

| Architecture | Description | Best For |
|---|---|---|
| **Single-Agent RAG** | One LLM controls retrieval loop | General Q&A, moderate complexity |
| **Multi-Agent RAG** | Retriever agents + evaluator agents | Cross-domain, parallel evidence gathering |
| **Hierarchical RAG** | Supervisor routes to specialized sub-agents | Multi-domain enterprise knowledge bases |
| **Corrective RAG** | Retrieval quality gating + fallback | High-stakes accuracy requirements |
| **Adaptive RAG** | Complexity-based routing | Mixed query workloads, cost optimization |
| **Graph-Based RAG** | Agent + graph traversal | Multi-hop reasoning, relational knowledge |

### Retrieval Decision Loop (LangGraph)

```python
from langgraph.graph import StateGraph, START, END
from typing import TypedDict, Literal

class RAGState(TypedDict):
    query: str
    context: list[str]
    retry_count: int
    confidence: float

def retrieve(state: RAGState) -> dict:
    """Hybrid retrieval with confidence scoring."""
    results = hybrid_retrieve(state["query"], k=5)
    confidence = eval_relevance(state["query"], results)
    return {"context": results, "confidence": confidence}

def should_generate(state: RAGState) -> Literal["generate", "rewrite", "fallback"]:
    """CRAG-style confidence gating."""
    if state["confidence"] > 0.7:
        return "generate"
    if state["retry_count"] < 3:
        return "rewrite"
    return "fallback"

def rewrite_query(state: RAGState) -> dict:
    """Rewrite query for better retrieval."""
    rewritten = llm.invoke(f"Rewrite this query for better search results: {state['query']}")
    return {"query": rewritten.content, "retry_count": state["retry_count"] + 1}

graph = StateGraph(RAGState)
graph.add_node("retrieve", retrieve)
graph.add_node("rewrite", rewrite_query)
graph.add_node("generate", generate_answer)
graph.add_node("fallback", generate_with_disclaimer)

graph.add_edge(START, "retrieve")
graph.add_conditional_edges("retrieve", should_generate)
graph.add_edge("rewrite", "retrieve")
graph.add_edge("generate", END)
graph.add_edge("fallback", END)
```

### Production Guardrails for Agentic Loops

| Guardrail | Rule |
|---|---|
| **Retry budget** | Cap at 3 retrieval cycles. After 3, return low-confidence answer with disclaimer. |
| **Tiered routing** | Simple queries → standard RAG. Complex → full corrective loop. Cuts cost 40-60%. |
| **Embedding cache** | Cosine distance <0.05 = reuse cached documents. Key by `SHA-256(text)`. |
| **Parallel execution** | Fire dense + sparse + graph retrievers concurrently, not sequentially. |
| **Observability** | Log every retrieval call: query, results, confidence, correction triggered. Use LangSmith, Arize Phoenix, or Maxim. |

---

## Chunking Strategies

How you split documents into chunks determines retrieval quality more than model choice. Bad chunking produces bad retrieval regardless of how sophisticated the pipeline is.

### Chunk Size Selection

| Chunk Size | Trade-off | Best For |
|---|---|---|
| Small (128-256 tokens) | Higher precision, more chunks to search, risk of losing context | Factoid Q&A, single-sentence answers |
| Medium (512-1024 tokens) | Balance of precision and context | General knowledge base queries |
| Large (1024-2048 tokens) | More context per chunk, lower precision, fewer chunks | Long-form synthesis, summarization |

### Overlap

Use 10-20% token overlap between adjacent chunks to avoid splitting relevant context across chunk boundaries. More overlap = better recall at chunk boundaries, but increases index size and cost.

### Chunking Methods

| Method | How It Works | When to Use |
|---|---|---|
| Fixed-size | Split every N tokens | Baseline; works for homogeneous text |
| Sentence-aware | Split on sentence boundaries | Narrative text, articles, reports |
| Paragraph-aware | Split on paragraph boundaries | Well-structured documents |
| Recursive character | LangChain default; tries paragraphs → sentences → characters | General-purpose fallback |
| Semantic | Embed sentences, split where embedding similarity drops | Premium accuracy; higher cost |
| Document-structure | Split on headers, sections, logical boundaries | Structured docs (legal, technical, academic) |

**For tabular data chunking specifically, see `tabular-data.md`** (50-100 row chunks, preserving headers).

### Metadata

Always store metadata with chunks: source document, page/section number, timestamp, and any relevant category tags. This enables filtered retrieval (search only within a specific document or date range) and proper citation in generated responses. The metadata you tag here is exactly what the pre-retrieval gate can later filter on — see [Metadata Filtering (Pre-Retrieval Gate)](#metadata-filtering-pre-retrieval-gate).

---

## Production Tooling

### Vector Databases with Native Hybrid Search

| Database | Sparse Support | Fusion | Notes |
|---|---|---|---|
| Qdrant | BM25 + SPLADE | RRF, DBSF | Best-in-class hybrid control |
| Elasticsearch 8.9+ | BM25 (native) | RRF built-in | Easiest if already on ES stack |
| Weaviate | BM25 | alpha parameter | Single-call hybrid API |
| pgvector + pg_textsearch | BM25 (true) | Manual | Full Postgres stack; see `deployment.md` |
| Redis 8.4 | BM25 | FT.HYBRID | Single atomic operation |
| Pinecone | SPLADE via sparse API | Weighted | Managed, no self-host |

> **Design axiom: Tiered escalation.** Start with pgvector if you already run Postgres (`deployment.md` recommends "use one database"). Move to Qdrant/Weaviate only when you need features pgvector lacks (native hybrid fusion, DBSF, built-in reranking).

### Dual-Store Architecture (Vector + Relational)

Some systems need *both* fuzzy semantic search and exact symbolic computation. Separate the two: route unstructured text through a vector store, and route facts, counts, sums, joins, ordering, and date math through a relational/SQL store. Each engine does what it is good at — embeddings cannot do exact aggregation reliably. This is the architectural answer to the global/structured queries that pure vector RAG fails (see `## Local RAG vs Global RAG`: LLMs are poor at counting/sorting/aggregation, so delegate those to SQL). Note this is *not* the same as the pure-structured-data case redirected to `tabular-data.md` at the top of this reference — dual-store is for systems that need semantic search *and* structured query together.

- **Query routing.** A router decides which store(s) a query touches: pure facts/ledgers → SQL; descriptive text → vector; multi-step → an agent. Increasingly the router is an LLM agent equipped with tools (a vector-search tool plus a SQL-query tool), letting it pick or combine stores per query. (This is the query-router-by-query-shape idea; the agentic supervisor/worker form appears in `scaffolding.md`.)
- **Hybrid pattern (SQL narrows, vector re-ranks).** First use SQL or keyword filtering to build a small candidate set (e.g., top-100 lexical matches, or the rows satisfying structured constraints), then run exact vector scoring/re-rank *within* that set. Common in pgvector: it avoids building and maintaining a large ANN index and keeps recall exact inside the candidate set. The reverse order (vector-search then SQL-filter) is the post-filtering pattern from the metadata-filtering subsection above. Production systems often fuse both directions with Reciprocal Rank Fusion (RRF).
- **Trade-offs.** *Consistency — the sync nightmare:* a row deleted in SQL whose vector survives makes the LLM hallucinate ghost data; the two stores must stay in lockstep. *Latency:* multiple round-trips plus a fusion/re-rank step. *Complexity:* two systems plus a router, and misrouting is a *silent* failure — a complex query sent only to vector search returns a plausible-but-incomplete answer with no error.
- **Overkill vs necessary.** Overkill for purely-unstructured semantic corpora — one vector store, or Postgres + pgvector serving both roles, is simpler. Necessary when queries demand exact computation over structured attributes (counts/sums/joins/date math), exactly the global-query failure class. Pragmatic middle: consolidate into ONE engine (Postgres + pgvector) first to dodge the sync nightmare and infra sprawl (this matches the "use one database" axiom above and in `deployment.md`); split into dedicated vector and SQL stores only when scale demands it. SQL/structured-data serialization and chunking live in `tabular-data.md`; pgvector infrastructure lives in `deployment.md` — route to both, do not duplicate them here.

### Framework Integration

| Framework | Agentic RAG Support | Key Strength |
|---|---|---|
| LangGraph | Native stateful graphs + cycles | Production default for agentic loops; checkpointing, HITL |
| LlamaIndex | Auto-routed, agentic workflows | Best abstraction for multi-index routing and advanced retrieval patterns |
| Haystack | DAG pipelines | Regulated industries; explicit, auditable |
| Semantic Kernel | Growing | Azure/Microsoft stack |

For detailed framework comparison, see `frameworks.md`. LlamaIndex is recommended when RAG is the primary capability; LangGraph when RAG is one tool among many in an agentic system.

---

## Retrieval Evaluation

For comprehensive RAG evaluation — the Q/A/C framework, 6 exhaustive metrics across 3 tiers, domain-severity mapping, and evaluation harness guidance — see `rag-evals.md`.

Quick reference for retrieval-specific operational metrics:

| Metric | What It Signals | Target |
|---|---|---|
| Retrieval cycles per query | First-stage quality (should stay low) | Median ≤1.5 |
| CRAG trigger rate | First-stage retrieval sufficiency | Lower is better |
| Latency P50/P95 per retrieval call | Performance budget | ≤120ms P50; flag if P95 >500ms |
| Cache hit rate | Steady-state efficiency | >30% |

---

## Decision Framework

```
Does the agent need to search a knowledge base?
  NO  → Skip this reference. Use text-tools.md for code search,
        tabular-data.md for structured data.
  YES ↓

Does the corpus fit in a single context window (<100K tokens)?
  YES → Load directly. No RAG needed.
  NO  ↓

Are queries keyword-heavy (IDs, codes, exact terms)?
  YES → BM25 must be in the stack (sparse mandatory).
  NO  → Dense-only may be sufficient.

Is the corpus domain-specific with specialized vocabulary?
  YES → Fine-tune embeddings or use SPLADE.
  NO  → Generic bi-encoder (bge, e5) is sufficient.

Are queries multi-hop or cross-document relational?
  YES → See multi-hop-rag.md for method selection:
        Predictable hops → Query Decomposition
        Variable/dependent hops → IRCoT
        Entity-relational → GraphRAG
        Latency-critical → REAPER
        Mixed workloads → Adaptive Routing + method per class
  NO  → Flat hybrid search.

Is precision at top-1 critical?
  YES → Add cross-encoder or ColBERT reranker.
  NO  → RRF fusion + top-5 to LLM is sufficient.

Are queries abstract or underspecified?
  YES → Add HyDE pre-retrieval step.
  NO  → Direct query embedding.

Is the system agentic (multi-step reasoning)?
  YES → CRAG-style confidence gating + retry loop (cap at 3).
        Tiered routing by query complexity.
  NO  → Static single-pass hybrid pipeline.
```

---

## Failure Modes

| Failure Mode | Symptom | Mitigation |
|---|---|---|
| **Stale index** | Correct answers exist in corpus but retrieval misses them | Incremental re-indexing pipeline; staleness monitoring (compare index timestamp to corpus update timestamp) |
| **Embedding drift** | Retrieval quality degrades after embedding model update | Version embeddings; re-index fully when changing models; track score distributions |
| **Vocabulary gap** | Dense retrieval misses domain-specific terms | Add BM25 to hybrid stack; fine-tune embeddings on domain data; use SPLADE |
| **Context poisoning** | Irrelevant retrieved docs cause hallucination | CRAG confidence gating; cross-encoder reranking; limit to top-3 high-confidence results |
| **Chunk boundary split** | Answer spans two chunks, neither is retrieved | Increase chunk overlap; use sentence/paragraph-aware chunking; add parent-document retrieval |
| **Over-retrieval** | Too many docs stuffed into context; LLM ignores or confuses them | Limit to top-k (3-5); compress retrieved context; use adaptive retrieval to skip when unnecessary |
| **Infinite retry loop** | Agentic loop rewrites query indefinitely | Hard cap at 3 retries; generate with disclaimer after cap |
| **Cold cache stampede** | All queries miss cache simultaneously under load | Pre-warm cache with common queries; use embedding similarity-based cache (cosine >0.95 = hit) |
| **Single-vector collapse** | Bi-encoder collapses semantically different queries to same embedding | Use ColBERT (per-token) for fine-grained matching; add a [metadata-filtering pre-retrieval gate](#metadata-filtering-pre-retrieval-gate) |

---

**See also:** `multi-hop-rag.md` for multi-hop methodology taxonomy, decision matrix, LangGraph implementation templates, and multi-hop evaluation metrics. `embeddings.md` for embedding model selection, evaluation protocols, and efficiency trade-offs (MRL truncation, quantization, domain-specific models). `text-tools.md` for code search and structured data filtering (just-in-time context, not pre-indexed RAG). `entity-resolution.md` for vector blocking in entity matching pipelines. `tabular-data.md` for tabular data chunking (50-100 row chunks). `deployment.md` for vector store infrastructure (pgvector, long-term memory). `evals.md` for the full evaluation framework including RAGAS. `production.md` for context engineering, cost modeling, and observability. `direct-corpus-interaction.md` for agentic grep-based retrieval (corpus-as-filesystem) when the corpus is large, evolving, or keyword-heavy and a vector index is overkill.
