# RAG Evaluation: The 6 Metrics Framework

Systematic evaluation framework for Retrieval-Augmented Generation systems. Based on the exhaustive combinatorial analysis of RAG's three core variables — every RAG failure maps to exactly one of six relationships.

For general agent evaluation (frameworks, benchmarks, safety, monitoring), see `evals.md`. For LLM-as-judge implementation, see `llm-as-judge.md`. For retrieval infrastructure (sparse/dense/hybrid search, reranking, chunking), see `retrieval.md`. For multi-hop retrieval evaluation, see `multi-hop-rag.md` §Evaluation.

## Table of Contents

1. [The Q/A/C Framework](#the-qac-framework)
2. [Tier 0: Retrieval Prerequisites](#tier-0-retrieval-prerequisites)
3. [Tier 1: The Three Core RAG Metrics](#tier-1-the-three-core-rag-metrics)
4. [Tier 2: Advanced Diagnostic Metrics](#tier-2-advanced-diagnostic-metrics)
5. [Domain-Severity Mapping](#domain-severity-mapping)
6. [Evaluation Cadence](#evaluation-cadence)
7. [Failure-to-Metric Mapping](#failure-to-metric-mapping)
8. [Building the RAG Evaluation Harness](#building-the-rag-evaluation-harness)

---

## The Q/A/C Framework

Every RAG system has exactly three variables:

| Variable | Definition |
|----------|-----------|
| **Q** (Question) | The user's query or prompt |
| **C** (Context) | The retrieved documents/chunks |
| **A** (Answer) | The generated response |

These three variables produce exactly **six conditional relationships** (X given Y). When a RAG system fails, one of these six is broken — no hidden factors exist.

| Relationship | Metric Name | Measures | Component Diagnosed |
|-------------|------------|---------|-------------------|
| C\|Q | Context Relevance | Is the retrieved context relevant to the question? | Retriever |
| A\|C | Faithfulness | Does the answer stick to what's in the context? | Generator |
| A\|Q | Answer Relevance | Does the answer address the user's question? | End-to-end |
| C\|A | Context Support | Does the context contain everything needed to support the answer? | Retriever completeness |
| Q\|C | Question Answerability | Can this question even be answered with this context? | Retriever + routing |
| Q\|A | Self-Containment | Can someone understand the question from the answer alone? | Generator completeness |

**Key insight:** Most vendor dashboards ship dozens of RAG metrics. Map each one back to these six relationships. If a metric doesn't clearly measure one of them, it's noise.

---

## Tier 0: Retrieval Prerequisites

If retrieval is broken, nothing downstream can save you. Evaluate these first — they're cheap (no LLM needed) and fast.

**Prerequisite:** Ground-truth labels. For each query, you need to know which chunks are actually relevant. Build this dataset using a reverse workflow: start from your knowledge base, generate realistic questions from specific chunks, creating perfectly aligned (Q, A, C) triplets.

### Retrieval Metrics

| Metric | What It Measures | Formula / Description | Target |
|--------|-----------------|----------------------|--------|
| **Precision@K** | Fraction of top-K results that are relevant | relevant_in_top_k / K | Depends on K; higher is better |
| **Recall@K** | Fraction of all relevant chunks found in top-K | relevant_in_top_k / total_relevant | >0.9 for K=10 |
| **MAP@K** | Average precision across queries, rewarding early relevant ranking | Mean of per-query average precision | >0.7 |
| **MRR@K** | Position of first relevant match | Mean of 1/rank_of_first_relevant | >0.7 |
| **nDCG@K** | Full ranking quality with graded relevance | Normalized discounted cumulative gain | >0.6 |

**MAP@K example:** Retrieved items [A, B, C, D, E] where A and C are relevant:

| Rank | Item | Relevant? | Precision at rank |
|------|------|----------|-------------------|
| 1 | A | Yes | 1/1 = 1.0 |
| 2 | B | No | — |
| 3 | C | Yes | 2/3 = 0.66 |
| 4 | D | No | — |
| 5 | E | No | — |

Average Precision = (1.0 + 0.66) / 2 = **0.83** (average only at relevant positions).

**When to use:** Daily development. Tuning embeddings, chunk sizes, A/B testing retrieval strategies. No LLM required — cheap and fast.

**When NOT to use:** As the sole evaluation. These tell you if search works, but not if the full system (retrieval + generation) works. You need both Tier 0 and Tier 1.

---

## Tier 1: The Three Core RAG Metrics

Every RAG application needs these three. They map to the most critical failure modes. Measured using LLM judges (see `llm-as-judge.md` for bias mitigation and rubric design, `binary-evals.md` for decomposition into binary questions).

### C|Q — Context Relevance

**What it measures:** Does the retrieved context address the question's information needs?

**What it diagnoses:** Retriever quality — if irrelevant passages are retrieved, the generator can't fix it.

**Example (financial assistant):**
- **Pass:** Query asks about Q4 dividend payouts → retrieved context contains user's dividend payment records from Q4.
- **Fail:** Query asks about Q4 dividend payouts → retrieved context contains general information about how dividends work and their tax implications.

**This is the most common RAG failure mode.** Search pulling educational content instead of actual data, or conceptually similar but factually irrelevant passages.

### A|C — Faithfulness

**What it measures:** Does the answer restrict itself to claims verifiable from the provided context?

**What it diagnoses:** Generator hallucination — did the model stay grounded in the documents?

**Example:**
- **Pass:** Context contains a CRM record showing a client meeting for portfolio rebalancing → answer states exactly that.
- **Fail:** Context contains the CRM record → answer adds hallucinated agenda items like "tax-loss harvesting strategies" not in the context.

**Critical distinction from Context Support (C|A):** Faithfulness looks at the answer and checks if it introduced claims that aren't in the context. Context Support (Tier 2) looks at the context and checks if it contains everything the answer needs. Different directions, different failures caught.

### A|Q — Answer Relevance

**What it measures:** Does the response directly address the user's question?

**What it diagnoses:** End-to-end user experience — even if context is good and answer is faithful, it must actually help the user.

**Example:**
- **Pass:** User asks how much investments grew last month → answer provides specific percentage change and dollar amount for their account.
- **Fail:** User asks how much investments grew last month → answer discusses general market performance without mentioning the user's actual account.

### Evaluation Approach

Run separate LLM judges per metric — one judge per dimension with dimension-specific rubrics. A single prompt evaluating all three simultaneously produces less consistent results. See `llm-as-judge.md` for rubric design and `binary-evals.md` for decomposing into binary pass/fail questions (+0.45 inter-evaluator agreement improvement).

---

## Tier 2: Advanced Diagnostic Metrics

These provide deeper diagnostic insights, typically needed in sensitive domains or when Tier 1 metrics can't explain a failure.

### C|A — Context Support

**What it measures:** Does the retrieved context contain all information needed to fully support every claim in the answer?

**Faithfulness vs Context Support — the subtle difference:**
- **Faithfulness (A|C):** "Did the answer deviate from the context?" → catches obvious hallucinations where the answer adds fabricated claims.
- **Context Support (C|A):** "Was the context sufficient to support the answer?" → catches the subtler case where the context was insufficient and the LLM silently filled gaps with plausible-sounding details.

**Example:** Answer says "total Q4 dividend income was $2,340 across 5 holdings, with the largest payout from MSFT at $890." Context only contains the total dividend amount of $2,340. The per-holding breakdown is nowhere in the retrieved documents. Faithfulness might pass (the total is correct), but Context Support fails — the context couldn't back the details.

### Q|C — Question Answerability

**What it measures:** Can the user's question even be resolved with this context?

**What it diagnoses:** Whether the system should attempt an answer at all. Critical for validating that agents say "I don't know" instead of confidently hallucinating from insufficient context.

**Example:** User asks about crypto portfolio performance, but retrieved documents only contain equity data. The question is unanswerable with this context — the system should refuse rather than guess.

**Especially important when:** The RAG architecture integrates external services and the agent must choose the right data source first. Wrong tool selection makes the question unanswerable regardless of retrieval quality within that source.

### Q|A — Self-Containment

**What it measures:** Can someone infer the original question from the answer alone? Does the output provide enough background to stand on its own?

**Example:**
- **Pass:** "Your portfolio's return for March 2026 was 12.4%, representing a $14,280 gain."
- **Fail:** "12.4%."

**Prioritize when:** Outputs are forwarded via email, logged in CRM notes, included in reports, or read without the original conversation context.

---

## Domain-Severity Mapping

Different domains require emphasis on different metrics. Match evaluation strictness to your domain's risk profile.

| Domain Severity | Examples | Primary Metrics | Retrieval Bias | Rationale |
|----------------|---------|----------------|---------------|-----------|
| **High** | Finance, medical, legal | Faithfulness (A\|C), Context Support (C\|A), Answerability (Q\|C) | Precision over recall | Every claim must be traceable. System must refuse when uncertain. |
| **Medium** | Customer support, technical docs | Answer Relevance (A\|Q), Answerability (Q\|C) | Recall over precision | Output must be helpful. Know when to hand off to a human. |
| **Low** | Research, writing, content generation | Context Relevance (C\|Q), Answer Relevance (A\|Q) | High recall | Synthesis and reframing expected. Faithfulness thresholds lower — generator adds value beyond raw text. |

**When to use all six:** Core conversational features with many silent failure modes. Evaluate the three core metrics (Tier 1) as baseline, extend to Tier 2 when failures can't be explained.

**When end-to-end is enough:** Structured output tasks where exact format with specific values is expected. Checking the final output against ground truth can be a better proxy than tracing every retrieval step. Sometimes assessing the destination matters more than checking the route.

---

## Evaluation Cadence

| Tier | Frequency | What | Cost | Integration Point |
|------|----------|------|------|------------------|
| **Tier 0** — Retrieval | Daily / per-commit | Precision@K, Recall@K, MAP@K, MRR@K | Cheap — no LLM | CI/CD pipeline |
| **Tier 1** — Core RAG | Weekly / pre-merge | Context Relevance, Faithfulness, Answer Relevance | Moderate — LLM judge | Feature branch merge gate |
| **Tier 2** — Advanced | Monthly / pre-release | Context Support, Answerability, Self-Containment | Expensive — LLM judge | Major release gate |

**Start from Tier 0 on day zero** with synthetic data. These metrics give quick feedback for tuning embeddings and chunk sizes. Only move to Tier 1 when Tier 0 metrics meet targets — if retrieval is broken, generation evals are unreliable.

---

## Failure-to-Metric Mapping

When your RAG system fails, identify the category and check the corresponding metrics:

| Failure Category | Symptoms | Metrics to Check | Root Cause |
|-----------------|----------|------------------|-----------|
| **Retrieval failure** | Irrelevant or missing context | Tier 0 metrics, Context Relevance (C\|Q) | Wrong embeddings, bad chunking, no reranking, stale index |
| **Generation failure** | Hallucinated details, unfaithful answers | Faithfulness (A\|C), Context Support (C\|A) | Model ignoring context, insufficient context, prompt issues |
| **End-to-end mismatch** | Correct retrieval + faithful answer but user unsatisfied | Answer Relevance (A\|Q), Self-Containment (Q\|A) | Answer technically correct but doesn't address actual need |
| **Scope failure** | System answers questions it shouldn't | Answerability (Q\|C) | No refusal logic, wrong data source selected |
| **Tool routing failure** | Right question, wrong data source queried | Answerability (Q\|C) + tool selection checks | Agent called wrong tool before retrieval |

---

## Building the RAG Evaluation Harness

### Dataset Preparation

RAG evaluation requires the full (Q, A, C) triplet — question, answer, AND retrieved context. The most common blind spot: treating RAG evaluation like generic LLM evaluation and never capturing what context the generator actually worked with.

**Two paths for building datasets:**

| Path | Source | Best For |
|------|--------|---------|
| **Manual expert QA** | Domain expert tests the app, records queries + results + judgments | Gold-standard quality, catches real failure modes |
| **Synthetic reverse workflow** | Start from knowledge base → extract facts → generate questions that require those specific chunks | Bootstrapping coverage across entire corpus, scaling cheaply |

**Context preparation challenge:** Each test case needs the right documents, chunks, and embeddings in the database. Running the full ingestion pipeline per eval run is slow and introduces variability.

**Solution:** Couple each test case with a database export (documents, chunks, embeddings, metadata). Inject directly into storage for each test — a context cache that bypasses the ingestion pipeline. Inject → query → evaluate → reset → next.

### Critical Design Rules

1. **Separate graders per dimension.** Don't ask one LLM to evaluate Context Relevance, Faithfulness, and Answer Relevance in a single prompt. Isolated judges with dimension-specific rubrics produce more consistent results.

2. **Include unanswerable queries.** Create scenarios where context deliberately lacks needed information. Without negative examples, your eval suite optimizes for always attempting an answer — directly exercises the Answerability (Q|C) metric.

3. **Check tool selection alongside RAG metrics.** If your RAG architecture integrates external services, add code-based checks for whether the agent invoked the correct data source. The best retrieval metrics can't help if the model queried the wrong service entirely.

4. **Log the full trace.** Record retrieved chunks (what the generator had access to), metadata (document IDs, similarity scores), and the context window sent to the LLM. When Faithfulness fails, check if the answer used information not provided. When Context Relevance fails, check which items ranked highest.

### Synthetic Dataset Generation

Use the reverse workflow to bootstrap from your knowledge base:

1. Start from document chunks in your corpus.
2. Use an LLM to extract key facts from specific passages.
3. Formulate realistic questions that can only be answered using that exact chunk set.
4. The resulting (Q, A, C) triplet is perfectly aligned by construction.

This technique is powerful for full-corpus coverage. Combine with expert QA samples for maximum evaluation quality.

### Example: Running Tier 1 RAG Evals with Opik

```python
from opik import Opik
from opik.evaluation.metrics import Hallucination, AnswerRelevancy, ContextRecall

client = Opik()

# Define metrics — one judge per dimension (never combine in single prompt)
metrics = [
    Hallucination(),        # A|C — Faithfulness (inverted: lower = better)
    AnswerRelevancy(),      # A|Q — Answer Relevance
    ContextRecall(),        # C|Q — Context Relevance
]

# Run evaluation against your dataset
results = client.evaluate(
    experiment_name="rag-eval-tier1",
    dataset=client.get_dataset("rag-golden-v1"),
    task=lambda sample: {
        "input": sample["question"],
        "output": my_rag_pipeline(sample["question"]),
        "context": get_retrieved_chunks(sample["question"]),
    },
    scoring_metrics=metrics,
)
```

For custom LLM judges with rubrics (recommended for Tier 2 metrics), see `llm-as-judge.md` and `binary-evals.md`.

---

## When NOT to Use This Framework

| Scenario | Use Instead |
|----------|------------|
| Agent doesn't use RAG (no retrieval step) | `evals.md` — general agent evaluation dimensions |
| Structured output tasks with exact expected format | End-to-end output comparison against ground truth — sometimes the destination matters more than the route |
| Evaluating retrieval infrastructure only (no generation) | Tier 0 metrics from this file, plus `retrieval.md` for tuning guidance |
| Multi-hop RAG with evidence chaining | Start here for the 6-metric baseline, then add multi-hop metrics from `multi-hop-rag.md` §Evaluation |

### Failure Modes

| Failure | Symptom | Fix |
|---------|---------|-----|
| Evaluating generation when retrieval is broken | All Tier 1 metrics are low and noisy | Fix Tier 0 first — if retrieval fails, generation evals are unreliable |
| Single judge for multiple dimensions | Inconsistent scores, dimension bleeding | Separate LLM judge per metric with dimension-specific rubrics |
| No unanswerable queries in eval set | System optimizes for always answering, never refusing | Add negative examples that exercise Answerability (Q\|C) |
| Treating Faithfulness and Context Support as the same | Missing subtle hallucinations where context was insufficient | Evaluate both: A\|C catches deviation, C\|A catches insufficiency |
| Ignoring tool routing in agentic RAG | Good retrieval metrics but wrong data source queried | Add code-based checks for tool selection alongside RAG metrics |
