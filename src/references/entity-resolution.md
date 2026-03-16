# Entity Resolution in Agentic Workflows: A Practical Guide

## What this guide covers

Entity resolution (ER) -- the process of determining whether two or more records refer to the same real-world entity -- is foundational infrastructure for AI agents. Agents that do research, answer questions over multiple documents, manage customer data, build knowledge graphs, or operate in regulated domains all depend on ER. Without it, an agent treats "Microsoft", "MSFT", "Microsoft Corporation", and "the Redmond-based tech giant" as four different things.

This guide covers how ER fits into agentic architectures, the dominant implementation patterns, the multi-agent decomposition that outperforms monolithic approaches, practical evaluation, and the specific domains where ER is a hard requirement.

---

## The three integration points

Entity resolution is not an agent. It is infrastructure that plugs into agentic workflows at three points:

**1. Pre-processing (NER + normalization).** Before an agent reasons over unstructured input, entities must be extracted and normalized. An LLM excels at this -- extracting defendant names from court records, product identifiers from invoices, company names from news articles. The extracted entities are then fed into a structured ER pipeline. This is the highest-consensus use of LLMs for ER: they are better at NER from messy, semi-structured text than traditional NLP pipelines, especially for edge cases like abbreviations, nicknames, and descriptive references ("the Russian President" instead of a name).

**2. Mid-workflow tool call.** During task execution, an agent encounters an entity mention and needs to resolve it against a known entity store. Example: a research agent finds "J.R.R. Tolkien" in one source and "the author of The Lord of the Rings" in another. The agent calls an ER tool/service to determine they refer to the same person before synthesizing information. This is the pattern used in RAG pipelines, data analysis agents, and customer service agents that need to link a caller to their account.

**3. Knowledge layer maintenance.** Agents that use knowledge graphs or persistent entity stores need ER to keep those stores clean. When new information arrives, ER determines whether it creates a new entity node or merges with an existing one. This is the KARMA pattern (NeurIPS 2025): specialized agents for entity extraction, schema alignment, and conflict resolution maintain a knowledge graph that other agents query.

---

## The canonical architecture: blocking + matching + clustering

The ER pipeline that works at scale, whether or not agents are involved, follows three stages:

### Stage 1: Blocking (candidate generation)

Reduce the O(n^2) comparison space to manageable candidate pairs. Without blocking, comparing 1M records means 500B pairwise comparisons.

**Methods (in order of increasing sophistication):**

- **Exact key blocking.** Hash on normalized name + zip code. Fast, misses variations.
- **Sorted neighborhood.** Sort by a key, compare within a sliding window.
- **LSH (Locality Sensitive Hashing).** Hash embeddings into buckets where similar items collide. Used by Google's Grale system for entity reconciliation.
- **Vector similarity (ANN).** Embed records, retrieve top-k nearest neighbors from a vector database (FAISS, Milvus, Pinecone). This is the dominant modern approach for semantic blocking.

For agentic workflows, vector blocking is the default. Embed each record (concatenate all fields into a single string, generate embedding), index in a vector store, and retrieve top-k candidates per query record.

### Stage 2: Matching (pairwise classification)

For each candidate pair, determine: same entity or not?

**Three approaches, from cheapest to most expensive:**

1. **Deterministic rules.** Exact match on ID fields, normalized string comparison, phonetic encoding (Soundex, Metaphone). Free, instant, high precision, low recall on messy data.

2. **Learned matchers.** Fine-tuned BERT/RoBERTa classifiers trained on labeled entity pairs. Peeters et al. (2024) showed fine-tuned Llama 3.1 and GPT-4o-mini exceed zero-shot GPT-4 performance by 1-10% F1 on standard benchmarks (WDC Products, DBLP-ACM, Abt-Buy). Cost: one-time training + cheap inference.

3. **LLM-as-matcher.** Zero-shot or few-shot LLM call with a binary prompt: "Do these two records refer to the same entity? Yes/No." GPT-4.1 achieves ~81% accuracy on Amazon-Google product matching. Expensive per-call but requires no training data. Best for low-volume or edge cases.

**The practical pattern: tiered matching.**

```
For each candidate pair:
  1. Try deterministic rules first (exact ID match, normalized name match)
     -> If match: LINK. If definite non-match: SKIP.
  2. For remaining ambiguous pairs, compute similarity score
     -> If above high threshold: LINK
     -> If below low threshold: SKIP
  3. For the gray zone between thresholds, call LLM-as-matcher
     -> Binary classification with reasoning
     -> If confidence low: route to human review queue
```

This tiered approach handles 80-90% of pairs with cheap deterministic/similarity methods, uses LLM calls only for the genuinely ambiguous cases, and reserves human review for the hardest edges. The multi-agent ER framework (Cakmak et al., 2025) achieved 94.3% accuracy with 61% fewer API calls than a monolithic LLM approach by using exactly this pattern.

### Stage 3: Clustering (transitive closure)

Individual pairwise match decisions must be consolidated into entity clusters. If A matches B and B matches C, then {A, B, C} should form one cluster even if A and C were never directly compared.

Methods: Union-Find (simple, fast), connected components on a match graph, correlation clustering (optimizes global consistency). In graph databases (Neo4j, FalkorDB), this is native graph traversal.

---

## Multi-agent ER: the architecture that works

The most significant recent result is that decomposing ER into specialized agents outperforms monolithic LLM approaches on accuracy, cost, and interpretability.

### The four-agent pattern (Cakmak et al., Computers 2025)

Implemented in LangGraph with a shared RAG layer:

**Agent 1: Direct Matcher.** Handles exact and near-exact matches via deterministic rules, abbreviation expansion, phonetic encoding. Invokes a lightweight LLM verification step only when ambiguity arises (e.g., shared surname and address fragment but different given name formatting).

**Agent 2: Indirect Matcher (Transitive Linker).** Evaluates whether two records that don't directly match might refer to the same entity via transitive linkage through intermediate records. Uses both numerical similarity thresholds and LLM-driven contextual inference. Performs A/B-linking to propagate inferred relationships, merging indirect matches into consistent clusters.

**Agent 3: Household Matcher (Cluster Builder).** Advances from individual-level linkage to collective entity grouping. Groups records by shared attributes (address, household identifiers) and validates clusters for internal consistency.

**Agent 4: Movement Detector (Temporal Tracker).** Tracks residential relocations and entity evolution over time. Handles the case where entities change attributes (name changes, address moves, company mergers) while maintaining identity continuity.

**Shared infrastructure:**
- RAG layer: each agent retrieves contextual information from a shared knowledge base
- State management: LangGraph manages execution flow, enabling feedback loops and conditional reprocessing based on intermediate confidence scores
- Audit trail: every decision is logged with reasoning, enabling full traceability

**Results on S12PX dataset (200-300 records):**
- 94.3% accuracy on name variation matching
- 61% reduction in API calls vs. single-LLM baseline
- Complete decision traceability

### The KARMA pattern for knowledge graph enrichment (NeurIPS 2025)

For agents that maintain knowledge graphs, KARMA defines seven specialized agents:

1. **Ingestion Agents** -- retrieve and normalize input documents
2. **Reader Agents** -- parse and segment relevant text sections
3. **Summarizer Agents** -- condense sections into domain-specific summaries
4. **Entity Extraction Agents** -- identify and normalize entities (LLM-based NER)
5. **Relationship Extraction Agents** -- infer relationships between entities
6. **Schema Alignment Agents** -- map new entities/relations to existing KG schemas
7. **Conflict Resolution Agents** -- classify contradictions as Contradict/Agree/Ambiguous, decide whether to discard, flag for review, or integrate with caution

Each agent uses specialized prompts and domain knowledge. The conflict resolution agent is particularly relevant: when a new triplet (DrugX, causes, DiseaseY) contradicts an existing triplet (DrugX, treats, DiseaseY), the agent must resolve this through evidence-based reasoning rather than simple overwrite.

---

## Where LLMs help and where they don't

### LLMs excel at

**Named Entity Recognition from unstructured text.** Extracting structured entity data from free text (court records, clinical notes, news articles, emails) is where LLMs provide the most value. They handle abbreviations, coreference ("he", "the company"), descriptive references, and multilingual content far better than traditional NER.

**Semantic matching for ambiguous pairs.** When deterministic methods can't decide -- "J. Smith, 123 Main St" vs. "John Smith, 123 Main Street" -- an LLM can reason about the probability these refer to the same person by considering all attributes jointly.

**Explanation generation.** LLMs can articulate *why* two records match or don't match in natural language, which is critical for regulated domains (AML, KYC) where audit trails must be human-readable.

**Edge case triage.** Replacing the human-in-the-loop for low-confidence matches that fall in the gray zone between automatic match and automatic non-match. Guardrails: require the LLM to justify each pairwise connection in natural language.

### LLMs struggle with

**Scale.** Pairwise LLM comparisons are O(n^2) in the naive case. Even with blocking, a dataset of 100K records might produce 1M candidate pairs. At $0.01/comparison, that's $10K per run. Deterministic/learned matchers handle this at negligible cost.

**Consistency and reproducibility.** LLMs are non-deterministic. The same pair might get different verdicts across runs. GPU floating-point effects mean even temperature=0 doesn't guarantee identical outputs. Strict idempotence is only achievable with specific hardware configurations at a performance penalty.

**Threshold tuning.** Rules-based ER allows precise adjustment of matching tolerances per use case. LLM-based ER provides no equivalent mechanism -- you can't tell the model "be 10% more lenient on address matching."

**Temporal entity evolution.** Entities change over time -- people change names, companies merge, addresses change. Representing transient linkage (records A-D linked only via intermediate records B-C in an entity graph) requires structured graph data, not LLM prompting.

**Regulatory determinism.** Financial and healthcare ER often requires deterministic, auditable matching logic. Current LLMs cannot guarantee consistent decisions across runs, which is a compliance blocker in some jurisdictions.

---

## The GenAI ER pipeline in code

The pattern that works in production: vector embedding for blocking + LLM for matching.

### Step 1: Embed and index

```python
from sentence_transformers import SentenceTransformer
import faiss
import numpy as np

model = SentenceTransformer('all-MiniLM-L6-v2')

def record_to_string(record: dict) -> str:
    """Concatenate all fields into a single string for embedding."""
    return " | ".join(f"{k}: {v}" for k, v in record.items() if v)

# Embed all records in the reference dataset
texts = [record_to_string(r) for r in reference_records]
embeddings = model.encode(texts, normalize_embeddings=True)

# Build FAISS index
index = faiss.IndexFlatIP(embeddings.shape[1])  # Inner product for cosine sim
index.add(embeddings.astype('float32'))
```

### Step 2: Block (retrieve candidates)

```python
def get_candidates(query_record: dict, top_k: int = 10) -> list:
    """Retrieve top-k candidate matches from the vector index."""
    query_text = record_to_string(query_record)
    query_embedding = model.encode([query_text], normalize_embeddings=True)
    scores, indices = index.search(query_embedding.astype('float32'), top_k)
    return [(reference_records[i], float(s)) for i, s in zip(indices[0], scores[0])]
```

### Step 3: Match (tiered)

```python
import json
from openai import OpenAI

client = OpenAI()

def deterministic_match(record_a: dict, record_b: dict) -> str:
    """Returns 'match', 'non_match', or 'uncertain'."""
    # Exact ID match
    if record_a.get('id') and record_a['id'] == record_b.get('id'):
        return 'match'
    # Normalized name exact match
    norm_a = record_a.get('name', '').lower().strip()
    norm_b = record_b.get('name', '').lower().strip()
    if norm_a and norm_b and norm_a == norm_b:
        return 'match'
    # Obvious non-match (different countries, different entity types)
    if record_a.get('country') and record_b.get('country'):
        if record_a['country'] != record_b['country']:
            return 'non_match'
    return 'uncertain'

def llm_match(record_a: dict, record_b: dict) -> dict:
    """Binary LLM-as-matcher for ambiguous pairs."""
    prompt = f"""You are an entity resolution expert. Determine whether these two records
refer to the same real-world entity.

Record A: {json.dumps(record_a)}
Record B: {json.dumps(record_b)}

Consider: name variations, abbreviations, typos, address formatting differences,
and temporal changes (people move, companies rename).

First explain your reasoning in 2-3 sentences. Then answer "Yes" or "No".

Output as JSON: {{"reasoning": "...", "same_entity": true/false, "confidence": 0.0-1.0}}"""

    response = client.chat.completions.create(
        model="gpt-4o-mini",  # Cost-effective for binary classification
        messages=[{"role": "user", "content": prompt}],
        temperature=0,
        response_format={"type": "json_object"}
    )
    return json.loads(response.choices[0].message.content)

def resolve_entity(query_record: dict, top_k: int = 10) -> list:
    """Full tiered ER pipeline."""
    candidates = get_candidates(query_record, top_k)
    matches = []

    for candidate, similarity_score in candidates:
        # Tier 1: deterministic
        det_result = deterministic_match(query_record, candidate)
        if det_result == 'match':
            matches.append({**candidate, '_match_method': 'deterministic', '_confidence': 1.0})
            continue
        if det_result == 'non_match':
            continue

        # Tier 2: similarity threshold
        if similarity_score > 0.95:
            matches.append({**candidate, '_match_method': 'similarity', '_confidence': similarity_score})
            continue
        if similarity_score < 0.5:
            continue

        # Tier 3: LLM for gray zone
        llm_result = llm_match(query_record, candidate)
        if llm_result.get('same_entity'):
            matches.append({
                **candidate,
                '_match_method': 'llm',
                '_confidence': llm_result.get('confidence', 0.0),
                '_reasoning': llm_result.get('reasoning', '')
            })

    return matches
```

### Step 4: Cluster

```python
class UnionFind:
    """Simple Union-Find for transitive closure of match decisions."""
    def __init__(self):
        self.parent = {}

    def find(self, x):
        if x not in self.parent:
            self.parent[x] = x
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])
        return self.parent[x]

    def union(self, x, y):
        px, py = self.find(x), self.find(y)
        if px != py:
            self.parent[px] = py

def cluster_matches(pairwise_matches: list[tuple]) -> dict:
    """Given a list of (id_a, id_b) match pairs, return entity clusters."""
    uf = UnionFind()
    for id_a, id_b in pairwise_matches:
        uf.union(id_a, id_b)

    clusters = {}
    for record_id in uf.parent:
        root = uf.find(record_id)
        clusters.setdefault(root, []).append(record_id)
    return clusters
```

---

## ER as an agent tool (MCP/function calling)

For agents built on LangChain, LangGraph, or similar frameworks, ER should be exposed as a tool the agent can call during task execution.

### Tool definition

```python
from langchain.tools import tool

@tool
def resolve_entity(
    entity_name: str,
    entity_type: str = "person",
    additional_attributes: dict = None
) -> list[dict]:
    """Resolve an entity mention against the entity store.

    Use this tool when you encounter an entity reference that might
    match existing records in the knowledge base. Returns a list of
    candidate matches with confidence scores and reasoning.

    Args:
        entity_name: The entity mention to resolve (e.g., "MSFT", "Dr. Smith")
        entity_type: One of "person", "organization", "location", "product"
        additional_attributes: Optional dict of extra context
            (e.g., {"address": "123 Main St", "date_of_birth": "1990-01-15"})

    Returns:
        List of matched entities with confidence scores.
        Empty list if no matches found.
    """
    query_record = {"name": entity_name, "type": entity_type}
    if additional_attributes:
        query_record.update(additional_attributes)
    return resolve_entity_pipeline(query_record)
```

### When agents should call ER

- **RAG with multiple sources.** Before synthesizing information from different documents about what might be the same entity. Without ER, the agent may present contradictory information about "Microsoft Corp" and "MSFT" as if they were separate companies.

- **Data analysis over messy datasets.** Customer records with duplicates, product catalogs with variant names, transaction logs with inconsistent merchant identifiers.

- **Research and investigation.** Tracing a person or organization across multiple databases, news sources, and public records. The AML/KYC use case is the canonical example.

- **Multi-turn conversation with context accumulation.** When a user refers to the same entity differently across turns ("my doctor", "Dr. Patel", "the physician at City Hospital"), the agent needs ER to maintain a consistent entity reference.

---

## Evaluation

### Standard benchmarks

| Benchmark | Domain | Records | Matches | Difficulty |
|-----------|--------|---------|---------|------------|
| Amazon-Google | Products | 4,589 | 1,300 | Medium |
| Abt-Buy | Products | 2,173 | 1,097 | Medium |
| DBLP-ACM | Bibliographic | 4,910 | 2,224 | Easy |
| DBLP-Scholar | Bibliographic | 66,879 | 5,347 | Hard (scale) |
| WDC Products | E-commerce | varies | varies | Hard (corner cases) |
| Walmart-Amazon | Products | 24,622 | 962 | Hard |
| S12PX | Census/admin | synthetic | varies | Hard (messy) |

### Metrics

**Precision.** Of the pairs the system said match, what fraction actually match? Critical when false positives are expensive (e.g., merging two different customer accounts).

**Recall.** Of the actual matching pairs, what fraction did the system find? Critical when false negatives are expensive (e.g., missing a sanctions match in AML).

**F1.** Harmonic mean of precision and recall. The standard single-number metric for ER.

**Pair completeness.** After blocking, what fraction of true matching pairs are in the candidate set? Measures blocking quality. Target: >95%.

**Reduction ratio.** What fraction of the O(n^2) comparison space was eliminated by blocking? Target: >99%.

**Cost per resolution.** Total API spend / number of resolved entities. The tiered architecture should keep this under $0.01/entity at scale.

### What good looks like

- Zero-shot GPT-4 on entity matching benchmarks: ~75-85% F1 depending on domain
- Fine-tuned Llama 3.1 / GPT-4o-mini: 80-90% F1, approaching or exceeding GPT-4 zero-shot
- Multi-agent ER (Cakmak et al.): 94.3% accuracy on name variations, with full traceability
- Human expert agreement on hard ER tasks: ~90-95%

The gap between LLM matchers and human experts is narrowing, but the cost differential remains enormous for large-scale ER. The tiered approach (deterministic first, learned matchers second, LLM for edge cases) is the only architecture that achieves both high accuracy and reasonable cost.

---

## Domain-specific patterns

### AML / KYC / Compliance

The highest-stakes ER domain. Regulatory requirements mandate:

- Entity resolution across sanctions lists, PEP databases, adverse media
- Ultimate Beneficial Ownership (UBO) identification through complex corporate structures
- Full auditability of every match decision with natural language reasoning
- Deterministic reproducibility for regulatory examination

The architecture: structured knowledge graphs for entity storage, graph inference for ownership chain traversal, agentic AI layer for analyst interaction and hypothesis testing. Entity resolution unifies fragmented data across legacy systems (one system has full company name, another just an email, a third only a physical address) into a single entity view.

Key constraint: LLMs alone cannot provide the deterministic matching and threshold control that regulators require. The practical approach uses LLMs for NER (extracting entities from adverse media, court filings, etc.) and for edge case adjudication, while relying on rules-based matching for the core resolution pipeline.

### Healthcare

Patient matching across hospital systems, insurance records, and clinical databases. Errors mean wrong medication, missed diagnoses, or duplicated medical histories.

Key challenges: common names, address changes, transcription errors in clinical notes, privacy constraints limiting available matching attributes. The Google Adaptive Precise Boolean rubric framework was originally developed for evaluating healthcare LLM responses but its entity-level precision metrics apply directly to patient matching evaluation.

### E-commerce / Product matching

Matching products across catalogs (Amazon vs. Google Shopping, internal catalog deduplication). High volume, moderate stakes, well-served by learned matchers.

This is the best-benchmarked ER domain. WDC Products, Amazon-Google, and Abt-Buy provide standardized evaluation. Fine-tuned models consistently outperform zero-shot LLMs here because labeled training data is abundant and product attributes are relatively structured.

### Knowledge graph construction

Every entity extracted from unstructured text must be resolved against the existing graph before insertion. Without ER, knowledge graphs accumulate duplicate nodes for the same entity, degrading both graph quality and downstream RAG performance.

Neo4j's LLM Knowledge Graph Builder handles this with entity extraction from documents, entity deduplication via string normalization and embedding similarity, and community detection for related entity clustering. GraphRAG approaches (Microsoft, LightRAG) depend on clean entity resolution for the entity graphs that power their retrieval.

---

## Cost analysis

### Per-comparison costs (approximate, March 2026)

| Method | Cost per pair | Latency | Accuracy |
|--------|--------------|---------|----------|
| Deterministic rules | ~$0 | <1ms | High precision, low recall |
| Embedding similarity | ~$0.0001 | <5ms | Good for blocking |
| Fine-tuned classifier | ~$0.0001 | <10ms | 80-90% F1 |
| GPT-4o-mini | ~$0.001 | ~500ms | 75-85% F1 |
| GPT-4o | ~$0.01 | ~1s | 80-85% F1 |
| GPT-4.1 | ~$0.02 | ~2s | ~81% accuracy |
| Human review | ~$0.50-2.00 | minutes | ~90-95% |

### Cost at scale

For 100K records with average 10 candidates per record (1M candidate pairs):

- **Pure LLM (GPT-4o):** 1M x $0.01 = **$10,000 per run**
- **Tiered (90% deterministic, 9% similarity, 1% LLM):** ~**$150 per run**
- **Multi-agent with blocking optimization:** ~**$100 per run** (61% fewer API calls)

The 100x cost difference between pure LLM and tiered approaches is why nobody runs production ER with LLM-only matching at scale.

---

## Implementation checklist

1. **Define your entity schema.** What entity types? What attributes per type? What constitutes a "match" in your domain?

2. **Build the blocking layer first.** Embed records, index in a vector store. Validate pair completeness (>95% of true matches in candidate set) before investing in matching.

3. **Start with deterministic rules.** Exact match on IDs, normalized names, phone numbers. Measure how much of your volume this handles (often 40-60%).

4. **Add a similarity threshold layer.** Cosine similarity or Jaccard on attribute sets. Tune the high-confidence and low-confidence thresholds on labeled data.

5. **Add LLM matching for the gray zone.** Binary prompt ("same entity? yes/no"), structured JSON output, reasoning before verdict. Use GPT-4o-mini or equivalent for cost efficiency.

6. **Build the human review queue.** Low-confidence LLM decisions route to human review. This is where you build your labeled dataset for future model fine-tuning.

7. **Implement transitive closure.** Union-Find or graph-based clustering to merge pairwise match decisions into entity clusters.

8. **Expose as an agent tool.** Wrap the pipeline in a tool definition with clear documentation so agents can call it during task execution.

9. **Evaluate on domain-specific labeled data.** Standard benchmarks are useful for validation but your production data will have different characteristics. Label 500-1000 pairs from your domain.

10. **Monitor for drift.** Entity distributions change. New name formats, new address patterns, mergers and acquisitions. Re-evaluate monthly.

---

## References

**Multi-agent ER:**
- Cakmak, M.C. et al. (2025). Multi-Agent RAG Framework for Entity Resolution. *Computers*, 14(12), 525. https://www.mdpi.com/2073-431X/14/12/525

**LLM entity matching benchmarks:**
- Peeters, R. et al. (2024). Entity Matching using Large Language Models. https://arxiv.org/abs/2310.11244

**Knowledge graph enrichment:**
- KARMA: Leveraging Multi-Agent LLMs for Automated Knowledge Graph Enrichment. NeurIPS 2025. https://openreview.net/pdf?id=k0wyi4cOGy

**LLMs and ER practical assessment:**
- Tilores. Can LLMs be used for Entity Resolution? https://tilores.io/content/Can-LLMs-be-used-for-Entity-Resolution

**Semantic entity resolution:**
- The Rise of Semantic Entity Resolution. Towards Data Science. https://towardsdatascience.com/the-rise-of-semantic-entity-resolution/

**Elasticsearch ER prototype:**
- Entity resolution with Elasticsearch & LLMs. Elastic Search Labs. https://www.elastic.co/search-labs/blog/entity-resolution-llm-elasticsearch

**GenAI ER pipeline:**
- Reveriano, F. (2025). Enhancing Entity Resolution Using Generative AI. https://medium.com/@reveriano.francisco/enhancing-entity-resolution-using-generative-ai-part-1-5c6fed1d037a

**KG construction with LLMs:**
- Neo4j LLM Knowledge Graph Builder. https://neo4j.com/blog/developer/llm-knowledge-graph-builder-release/
- Ling, Y. et al. (2026). A review of knowledge graph construction using LLMs in transportation. *Transportation Research Part C*, 183. https://doi.org/10.1016/j.trc.2025.105428

**Compliance / AML:**
- DataWalk. UBO Identification in AML: Why LLMs Fail & How Agentic AI Delivers Accuracy. https://datawalk.com/ubo-identification-why-llms-fail-how-composite-ai-delivers-accuracy/
