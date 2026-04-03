# Multi-Hop RAG Methodologies

Patterns for answering questions that require reasoning across 2-N pieces of evidence scattered across a corpus. Standard RAG retrieves passages similar to a single query. Multi-hop RAG connects evidence chains: the answer to sub-question 1 determines what to retrieve for sub-question 2.

**When to use this reference:** The agent must answer questions requiring cross-document reasoning, entity-relationship traversal, temporal chains, or causal inference across multiple evidence fragments. This is NOT for single-hop factoid retrieval -- use `retrieval.md` §1-8 for that.

> **Design axiom: Tiered escalation.** Most queries are single-hop. Running full multi-hop on everything wastes 40-60% of compute. Route by complexity: simple factoid -> single-hop dense, moderate -> hybrid, complex multi-hop -> agentic loop. See [Adaptive Routing](#8-adaptive-routing).

## Table of Contents

1. [When Multi-Hop vs. When Not](#when-multi-hop-vs-when-not)
2. [Taxonomy of Approaches](#taxonomy-of-approaches)
3. [Decision Matrix](#decision-matrix)
4. [Implementation: LangGraph Multi-Hop](#implementation-langgraph-multi-hop)
5. [Multi-Hop Evaluation](#multi-hop-evaluation)
6. [Production Consensus](#production-consensus)
7. [Failure Modes](#failure-modes)

---

## When Multi-Hop vs. When Not

| Scenario | Recommendation |
|---|---|
| Query answerable from a single passage | Not multi-hop. Standard hybrid retrieval (`retrieval.md` §6). |
| Query requires combining 2+ facts from different documents | Multi-hop. Start with Query Decomposition or IRCoT. |
| Query traverses entity relationships ("X's supplier's risk exposure") | Multi-hop + graph. Use GraphRAG or HopRAG. |
| Query requires temporal chain reasoning ("what happened after X caused Y") | Multi-hop. IRCoT handles variable-hop chains best. |
| Query is thematic/global ("main themes across 500 reports") | Not multi-hop per se. RAPTOR or GraphRAG global search. |
| Corpus fits in context window (<100K tokens) | Skip multi-hop retrieval. Load everything. Let the LLM reason directly. |

> **Design axiom: Model costs first.** Each hop adds embedding cost + retrieval latency + LLM reasoning tokens. A 3-hop query costs ~3x a single-hop query. Calculate whether multi-hop is justified vs. stuffing more context.

---

## Taxonomy of Approaches

### 1. Query Decomposition (Plan-then-Execute)

The LLM decomposes a complex query into atomic sub-questions before any retrieval happens. Each sub-question is dispatched independently, results are aggregated with provenance, and the LLM synthesizes a final answer.

```
[Complex Query] -> [LLM: generate sub-questions]
    -> [Retrieve per sub-question] -> [Aggregate with provenance] -> [Synthesize]
```

**Key systems:**
- **A-RAG**: Exposes keyword, semantic, and chunk-level retrieval tools directly to the agent. 94.5% on HotpotQA, 89.7% on 2WikiMultiHop.
- **Self-Ask**: LLM generates follow-up questions explicitly, answers each with retrieval, chains answers.
- **DecomP**: Hardcoded decomposition patterns. Strong on predictable 2-hop datasets, fails on variable-hop (MuSiQue).

**When to use:** Hop structure is predictable (bridge questions, comparison questions). Sub-questions are independently answerable. You can enumerate what to retrieve upfront.

**When NOT to use:** What to retrieve at step N depends on what was found at step N-1 (use IRCoT instead). Sub-questions are not independently answerable.

**Limitation:** Decomposition quality is the ceiling. The LLM must predict what evidence exists before seeing it. Bad sub-questions produce bad retrieval.

---

### 2. Interleaved Retrieval and Reasoning (IRCoT)

Interleaves retrieval with chain-of-thought steps. What to retrieve at step N depends on what was derived at step N-1. This is the most general multi-hop pattern.

**Mechanism:**
1. Retrieve K documents using the original question
2. Generate next CoT sentence from question + retrieved docs + prior CoT
3. Use the last CoT sentence as a new retrieval query
4. Repeat until answer or max steps

**Results:** Up to 21-point retrieval improvement and 15-point F1 gain on HotpotQA, 2WikiMultihopQA, MuSiQue, and IIRC.

**Variants:**
| Variant | Distinction |
|---|---|
| **FLARE** | Triggers retrieval only when generation confidence drops below threshold |
| **DRAGIN** | Refines when and how new queries are issued during generation |
| **ReAct** | Explicit SEARCH/LOOKUP actions interleaved with reasoning traces |

**When to use:** Variable-hop queries. Open-domain reasoning where you cannot predict the evidence chain upfront. The answer to hop 1 determines what to search for in hop 2.

**When NOT to use:** Latency-critical systems (each hop adds a full LLM + retrieval cycle). Predictable hop structures where decomposition is simpler and cheaper.

---

### 3. Graph-Based Multi-Hop Retrieval

Builds an explicit graph structure over the corpus, then traverses edges to gather connected evidence. Best when the reasoning is fundamentally relational.

| System | Mechanism | Trade-off |
|---|---|---|
| **Microsoft GraphRAG** | Entity graphs + Leiden community clustering + hierarchical summaries. Local search = graph-aware passage retrieval; global search = community summaries. | High construction cost. Degrades above ~3M tokens corpus. 5-20 point gain on multi-hop benchmarks. |
| **HopRAG** | Passage graph with LLM-generated pseudo-queries as edges. Retrieve-reason-prune mechanism with "Helpfulness" metric. | Strong on logical relevance gaps. Medium construction cost. |
| **HippoRAG** | Personalized PageRank over knowledge graphs. Memory-inspired retrieval. | Novel approach; less production-proven. |
| **LightRAG / GLightRAG** | Simplified KG structures. | 10-50x lower construction cost vs. full GraphRAG; trades some accuracy. |
| **NodeRAG** | Heterogeneous graph (entities, relationships, chunks, events, summaries all as nodes). | Outperforms GraphRAG and LightRAG in indexing time and query efficiency. |
| **CatRAG** | Symbolic anchoring + query-aware dynamic edge weighting + key-fact passage enhancement. | Introduces "reasoning completeness" metric for evidence chain recovery. |

**When to use:** Queries traverse entity relationships across multiple documents. Relational reasoning ("indirect exposures," "supply chain dependencies"). Corpus has clear entity-relationship structure.

**When NOT to use:** Simple factoid queries (flat hybrid search is sufficient and faster). Corpora >3-5M tokens (graph traversal becomes less discriminative). No entity-relationship structure in the data.

> **Design axiom: Model costs first.** GraphRAG ROI is proportional to query reasoning depth. If <20% of your queries are multi-hop relational, the construction cost is not justified. Use adaptive routing to send only relational queries to the graph path.

---

### 4. Tree-Structured Retrieval (RAPTOR)

Builds a tree of increasingly abstract document summaries via recursive clustering and LLM summarization. Retrieval targets any level: raw chunks (specific), mid-level summaries (intermediate), top-level abstractions (thematic).

**When to use:** Long-document comprehension where thematic structure matters (annual reports, policy docs, legal filings). Global/thematic queries over large corpora.

**When NOT to use:** Factoid or entity-specific queries. Rapidly changing corpora (tree must be rebuilt on updates).

---

### 5. Corrective / Self-Critical Loops

Multi-pass rather than multi-hop: the system evaluates its own retrieval and re-retrieves on failure. These compose with any multi-hop method as a quality layer.

| System | Mechanism |
|---|---|
| **CRAG** | Lightweight retrieval evaluator scores documents. Actions: Correct (use context), Incorrect (discard, web search fallback), Ambiguous (keep + augment). Adds 100-800ms latency. |
| **Self-RAG** | Generator outputs inline reflection tokens: `[Retrieve]`, `[ISREL]`, `[ISSUP]`, `[ISUSE]`. Signals whether retrieval is needed, passages are relevant, generation is supported. |
| **SCMRAG** | Graph retriever + self-corrective agent. Significant improvements in retrieval precision and hallucination reduction. |

**When to use:** High-stakes accuracy requirements. Layer on top of any multi-hop method. Non-negotiable for production systems where wrong answers have consequences.

**When NOT to use:** Latency budget <200ms total (corrective loop adds 100-800ms per cycle).

> **Design axiom: Document failure modes.** Cap corrective retry loops at 3 cycles. Beyond that, return a low-confidence answer with disclaimer. Infinite correction is a latency bomb, not a quality guarantee.

See also: `retrieval.md` §8 (corrective loop implementation), `scaffolding.md` §RAG (CRAG topology).

---

### 6. Plan-then-Retrieve (Latency-Optimized)

Generates the full retrieval plan in one LLM pass (which sources, which queries, what order), then executes the plan without further LLM reasoning. Trades reasoning flexibility for latency.

| System | Mechanism | Performance |
|---|---|---|
| **REAPER** | LLM-based planner generates retrieval plan upfront, then executes. | 207ms retrieval latency, 96% tool accuracy. |
| **RAP-RAG** | Heterogeneous weighted graph index + adaptive planner selects retrieval method per query feature. | 3-5% accuracy improvement over GraphRAG/LightRAG baselines. |

**When to use:** Latency-critical production systems. Queries have predictable retrieval patterns. You can afford slightly less reasoning flexibility.

**When NOT to use:** Highly variable queries where the retrieval plan cannot be determined upfront. When reasoning quality trumps latency.

---

### 7. Beam / Search-Tree Approaches

Maintain multiple candidate reasoning paths in parallel, exploring the evidence space as a search tree rather than a single chain.

| System | Mechanism |
|---|---|
| **BeamAggR** | Beam aggregation reasoning over multi-source knowledge. Maintains parallel candidate paths, aggregates evidence across beams. |
| **DualRAG** | Dual-process (System 1 fast + System 2 slow) reasoning with retrieval. |
| **TreePS-RAG** | Tree-based process supervision. Treats multi-hop trajectory as a tree, supervises at each node. |

**When to use:** High-value queries where exploring multiple reasoning paths increases answer quality. Research-grade applications where cost is secondary.

**When NOT to use:** Cost-sensitive production systems (beam width multiplies LLM calls). Simple 2-hop queries where a single chain suffices.

---

### 8. Adaptive Routing

Meta-pattern: classify query complexity, route to the appropriate retrieval strategy. Not a multi-hop method itself, but the cost-control layer that makes multi-hop economically viable.

```
[Query] -> [Complexity Classifier]
  Simple factoid   -> single-hop dense retrieval
  Moderate          -> hybrid retrieval (dense + sparse)
  Complex multi-hop -> full agentic loop (IRCoT, decomposition, or graph)
```

Reduces cost 40-60% without meaningful quality loss. The DSPy `MultiHopRAG` module provides a clean implementation: iterative query generation + retrieval for N hops, with hop count as a parameter.

**When to use:** Any production multi-hop system. Mixed query workloads where most queries are single-hop but some require multi-hop.

**When NOT to use:** All queries are known to be multi-hop (uniform workload; routing adds overhead without benefit).

---

## Decision Matrix

| Method | Best For | Latency | Corpus Size Limit | Accuracy Gain vs. Vanilla RAG |
|---|---|---|---|---|
| Query Decomposition | Predictable hop structures, bridge/comparison questions | Medium | None | 10-20% |
| IRCoT | Variable-hop, open-domain, dependent evidence chains | High | None | Up to 15 pts (F1) |
| GraphRAG | Relational/entity reasoning, multi-doc entity traversal | Medium-High | ~3M tokens | 5-20 pts |
| HopRAG | Logical relevance gaps, pseudo-query edge traversal | Medium | Moderate | Significant F1 gains |
| RAPTOR | Thematic/hierarchical docs, global queries | Low | Large | Moderate |
| CRAG Loop | High-stakes accuracy (layer on any method) | Medium | None | Recall >90% (with hybrid) |
| REAPER | Latency-critical production, predictable queries | Low (207ms) | None | Comparable accuracy, much faster |
| Adaptive Routing | Mixed workloads, cost optimization | Variable | None | Cost reduction, not accuracy gain |

**Selection heuristic:**
1. Start with **Adaptive Routing** to classify query complexity
2. For predictable hops: **Query Decomposition**
3. For variable/dependent hops: **IRCoT**
4. For relational/entity queries: **GraphRAG** (or lightweight variant)
5. For latency-critical: **REAPER**
6. Layer **CRAG** on top of any method for high-stakes accuracy
7. For thematic/global queries over long documents: **RAPTOR**

---

## Implementation: LangGraph Multi-Hop

### IRCoT-Style Interleaved Retrieval

The most general multi-hop pattern. Each reasoning step produces a new retrieval query based on accumulated evidence.

```python
from langgraph.graph import StateGraph, START, END
from typing import TypedDict, Annotated, Literal
import operator

class MultiHopState(TypedDict):
    query: str
    reasoning_chain: Annotated[list[str], operator.add]   # CoT steps accumulated
    evidence: Annotated[list[dict], operator.add]          # {content, source, hop_number}
    current_hop_query: str                                  # derived query for next hop
    hop_count: int
    max_hops: int
    confidence: float
    answer: str

def retrieve_hop(state: MultiHopState) -> dict:
    """Retrieve documents for current hop query."""
    query = state["current_hop_query"] or state["query"]
    results = hybrid_retrieve(query, k=5)
    evidence = [
        {"content": r.content, "source": r.metadata["source"], "hop_number": state["hop_count"]}
        for r in results
    ]
    return {"evidence": evidence}

def reason_and_plan_next(state: MultiHopState) -> dict:
    """Generate next CoT step and derive next retrieval query."""
    prompt = f"""Question: {state["query"]}
Evidence so far: {state["evidence"]}
Reasoning so far: {state["reasoning_chain"]}

Generate the next reasoning step. If you have enough evidence to answer, say "SUFFICIENT".
Otherwise, state what information is still needed and formulate a search query for it."""

    response = llm.invoke(prompt)
    step = response.content

    if "SUFFICIENT" in step:
        return {
            "reasoning_chain": [step],
            "confidence": 0.9,
        }

    # Extract the next search query from the reasoning step
    next_query = llm.invoke(
        f"Extract a concise search query from this reasoning step: {step}"
    ).content

    return {
        "reasoning_chain": [step],
        "current_hop_query": next_query,
        "hop_count": state["hop_count"] + 1,
    }

def should_continue(state: MultiHopState) -> Literal["retrieve", "generate", "give_up"]:
    """Route based on confidence and hop budget."""
    if state["confidence"] > 0.7:
        return "generate"
    if state["hop_count"] >= state["max_hops"]:
        return "give_up"
    return "retrieve"

def generate_answer(state: MultiHopState) -> dict:
    """Synthesize final answer from accumulated evidence and reasoning."""
    prompt = f"""Question: {state["query"]}
Evidence chain: {state["evidence"]}
Reasoning chain: {state["reasoning_chain"]}

Synthesize a final answer. Cite sources for each claim."""
    answer = llm.invoke(prompt).content
    return {"answer": answer}

def generate_with_disclaimer(state: MultiHopState) -> dict:
    """Generate best-effort answer after exhausting hop budget."""
    answer = llm.invoke(
        f"Answer based on partial evidence (may be incomplete): "
        f"Q: {state['query']} Evidence: {state['evidence']}"
    ).content
    return {"answer": f"[Low confidence - {state['hop_count']} hops exhausted] {answer}"}

# Wire the graph
graph = StateGraph(MultiHopState)
graph.add_node("retrieve", retrieve_hop)
graph.add_node("reason", reason_and_plan_next)
graph.add_node("generate", generate_answer)
graph.add_node("give_up", generate_with_disclaimer)

graph.add_edge(START, "retrieve")
graph.add_edge("retrieve", "reason")
graph.add_conditional_edges("reason", should_continue)
graph.add_edge("generate", END)
graph.add_edge("give_up", END)

multi_hop_rag = graph.compile()

# Usage
result = multi_hop_rag.invoke({
    "query": "What is the risk exposure of Company A through Company B's primary supplier?",
    "reasoning_chain": [],
    "evidence": [],
    "current_hop_query": "",
    "hop_count": 0,
    "max_hops": 3,  # cap at 3 hops
    "confidence": 0.0,
    "answer": "",
})
```

### Query Decomposition with Parallel Retrieval

For predictable hop structures where sub-questions are independently answerable.

```python
class DecompState(TypedDict):
    query: str
    sub_questions: list[str]
    sub_answers: Annotated[list[dict], operator.add]   # {question, answer, sources}
    final_answer: str

def decompose(state: DecompState) -> dict:
    """Break complex query into atomic sub-questions."""
    response = llm.with_structured_output(SubQuestions).invoke(
        f"Break this into independent sub-questions: {state['query']}"
    )
    return {"sub_questions": response.questions}

def retrieve_and_answer_sub(state: DecompState) -> dict:
    """Retrieve and answer each sub-question. Use Send() for parallel fan-out."""
    # In LangGraph, use Send() API for parallel sub-question processing
    results = []
    for q in state["sub_questions"]:
        docs = hybrid_retrieve(q, k=3)
        answer = llm.invoke(f"Answer based on context: {docs}\nQuestion: {q}").content
        results.append({"question": q, "answer": answer, "sources": [d.metadata["source"] for d in docs]})
    return {"sub_answers": results}

def synthesize(state: DecompState) -> dict:
    """Combine sub-answers into final answer with provenance."""
    prompt = f"""Original question: {state["query"]}
Sub-answers: {state["sub_answers"]}
Synthesize a complete answer. Cite which sub-answer supports each claim."""
    return {"final_answer": llm.invoke(prompt).content}
```

### Multi-Hop State Shape (Reusable)

Extend the RAGState from `scaffolding.md` for multi-hop:

```python
class MultiHopRAGState(TypedDict):
    # Core RAG fields (from scaffolding.md)
    query: str
    retrieved_docs: Annotated[list[dict], operator.add]
    confidence: float
    retry_count: int
    generated_answer: str
    faithfulness_score: float
    status: Literal["retrieving", "reasoning", "generating", "done", "failed"]
    # Multi-hop extensions
    hop_count: int
    max_hops: int                                            # cap at 3-4
    reasoning_chain: Annotated[list[str], operator.add]      # CoT steps
    evidence_chain: Annotated[list[dict], operator.add]      # per-hop evidence with provenance
    sub_questions: list[str]                                  # for decomposition approach
    current_hop_query: str                                    # derived query for next hop
    method: Literal["ircot", "decomposition", "graph"]       # which multi-hop method is active
```

---

## Multi-Hop Evaluation

Standard IR metrics from `retrieval.md` §13 still apply. Add these multi-hop-specific metrics:

### Retrieval Metrics

| Metric | What It Measures | Target |
|---|---|---|
| Evidence chain recall | Were all required evidence fragments retrieved across hops? | >0.8 |
| Hop efficiency | Correct answer hops / actual hops taken | >0.7 (lower = wasted hops) |
| Cross-document precision | Of retrieved docs from different sources, how many were relevant? | >0.7 |

### Reasoning Metrics

| Metric | What It Measures | Target |
|---|---|---|
| Reasoning path correctness | Does the CoT follow a valid inference chain? (LLM-as-judge) | >0.8 |
| Intermediate answer accuracy | Are intermediate hop answers correct? | >0.85 |
| Answer completeness | Does the final answer integrate all required evidence? | >0.8 |

### Operational Metrics

| Metric | What It Signals |
|---|---|
| Hops per query (P50/P95) | Efficiency. P50 should be <=2 for most workloads. P95 >4 = decomposition or routing issue. |
| Hop budget exhaustion rate | % of queries hitting max_hops without sufficient confidence. >10% = method or routing problem. |
| Cost per multi-hop query | Track separately from single-hop. Should justify the accuracy gain. |
| Multi-hop routing accuracy | % of queries correctly classified as needing multi-hop. False positives waste cost; false negatives miss answers. |

### Key Benchmarks

| Benchmark | Characteristics | Discriminative Power |
|---|---|---|
| **HotpotQA** | 2-hop, bridge/comparison questions | Standard; easy for modern methods |
| **2WikiMultiHopQA** | 2-hop, predictable decomposition | Good for decomposition methods; less discriminative for IRCoT |
| **MuSiQue** | Variable-hop (2-4), harder decomposition | Best discriminator of methodology quality |
| **MultiHop-RAG** | News-based, cross-document evidence synthesis | Production-relevant |
| **GRADE** | 2D difficulty matrix (reasoning depth x retrieval difficulty), 2-5 hops | Most granular; error rates increase with both dimensions |

---

## Production Consensus

Best practices from production multi-hop systems (2025-2026):

1. **Hybrid retrieval (dense + sparse via RRF) is the floor.** Every multi-hop method benefits from better first-stage retrieval. Do not build multi-hop on top of dense-only retrieval.

2. **Reranking after fusion gives the highest single precision gain** regardless of which multi-hop strategy sits on top. Cross-encoder or ColBERT reranking at each hop, not just the first.

3. **Cap retrieval retry loops at 3 cycles.** Beyond that, return a low-confidence answer with disclaimer. This applies to both corrective loops and hop budgets.

4. **GraphRAG ROI is proportional to query reasoning depth.** If <20% of queries need relational reasoning, the graph construction cost is not justified. Use adaptive routing.

5. **Adaptive routing is mandatory for cost control.** Running full agentic multi-hop on simple factoid queries wastes 40-60% of compute. Classify, then route.

6. **Observability is non-negotiable.** Log every retrieval call, confidence score, hop count, and corrective action per query. Track hop budget exhaustion rate. Standard tools: LangSmith, Arize Phoenix, Maxim.

7. **Intermediate evidence must carry provenance.** Every hop's evidence must record: source document, retrieval method, confidence score, and hop number. Without this, you cannot debug multi-hop failures.

---

## Failure Modes

| Failure Mode | Symptom | Mitigation |
|---|---|---|
| **Bad decomposition** | Sub-questions miss the actual information need; final answer is wrong despite good retrieval per sub-question | Validate decomposition quality (LLM-as-judge on sub-questions). Fall back to IRCoT for queries that resist clean decomposition. |
| **Evidence chain break** | Hop N retrieves nothing relevant; reasoning chain stalls or hallucinates a bridge | Detect low-confidence hops. Rewrite hop query. If 2 consecutive hops return low confidence, fall back to broader retrieval. |
| **Hop budget exhaustion** | Max hops reached without sufficient evidence; >10% of queries hit the cap | Increase max_hops cautiously (cost grows linearly). More likely: improve first-stage retrieval or query routing. |
| **Redundant hops** | Multiple hops retrieve overlapping information; hop efficiency <0.5 | Deduplicate evidence across hops. Check if earlier evidence already answers the query before continuing. |
| **Reasoning drift** | CoT steps diverge from the original question; later hops retrieve irrelevant content | Re-anchor each reasoning step to the original question. Include the original query in every hop's prompt. |
| **Contradictory evidence** | Different hops retrieve conflicting facts; no resolution strategy | Detect conflicts explicitly. Present conflicts to the LLM with instructions to reconcile or flag uncertainty. Never silently pick one. |
| **Over-routing to multi-hop** | Adaptive router sends simple queries to multi-hop path; cost waste | Measure routing accuracy. False-positive rate for multi-hop classification should be <5%. |
| **Graph staleness** | Entity graph doesn't reflect recent corpus updates; traversal misses new relationships | Incremental graph updates on corpus change. Monitor graph freshness vs. corpus freshness. |

---

**See also:** `retrieval.md` for the full retrieval stack (sparse, dense, hybrid, reranking, corrective loops, chunking). `scaffolding.md` §RAG for single-hop RAG scaffolding and CRAG topology. `patterns.md` §STORM for iterative research pattern (a form of multi-hop). `embeddings.md` for embedding model selection. `evals.md` for the full evaluation framework. `production.md` for context engineering and cost modeling.
