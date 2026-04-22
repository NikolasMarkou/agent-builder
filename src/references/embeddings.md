<!-- benchmarks-as-of: 2026-04 -->
# Embedding Model Selection and Evaluation

Guidance for selecting, evaluating, and deploying embedding models in agent systems. Covers intrinsic evaluation, task-specific evaluation protocols, production readiness testing, domain-specific model recommendations, and efficiency trade-offs.

**When to use this reference:** The agent uses dense retrieval, semantic search, text classification via embeddings, clustering, or any component where embedding model choice materially affects output quality. This is the "which embedding model and how do I know it works" reference — for retrieval architecture (sparse/dense/hybrid, reranking, chunking, agentic RAG), see `retrieval.md`.

> **Design axiom: Calibrate on real data.** Leaderboard scores (MTEB, BEIR) are aggregates across heterogeneous datasets. No model dominates every task. Models that top the STS subtab routinely underperform in retrieval. Always evaluate on a held-out sample of your own data before committing to a model.

## Table of Contents

1. [Why Leaderboards Are Insufficient](#why-leaderboards-are-insufficient)
2. [Three-Pillar Evaluation Framework](#three-pillar-evaluation-framework)
3. [Task-Specific Evaluation Protocols](#task-specific-evaluation-protocols)
4. [When Embeddings Are Not Enough](#when-embeddings-are-not-enough)
5. [Model Selection Decision Framework](#model-selection-decision-framework)
6. [Intrinsic Evaluation Methods](#intrinsic-evaluation-methods)
7. [Extrinsic Evaluation Methods](#extrinsic-evaluation-methods)
8. [Production Readiness Testing](#production-readiness-testing)
9. [Efficiency Trade-offs](#efficiency-trade-offs)
10. [Domain-Specific Considerations](#domain-specific-considerations)
11. [Benchmarks Reference](#benchmarks-reference)
12. [Model Reference by Task](#model-reference-by-task)
13. [Evaluation Checklist](#evaluation-checklist)

---

## Why Leaderboards Are Insufficient

MTEB and BEIR aggregate scores mask task-specific weaknesses. Root causes of leaderboard-to-production mismatch:

| Cause | Problem |
|---|---|
| **Domain shift** | Leaderboard corpora (MS MARCO, NQ) are general-domain. Legal, biomedical, code, financial corpora have distinct vocabulary distributions. |
| **Length asymmetry** | Production queries may be 5 tokens against 2,000-token documents. Models with different pooling strategies behave differently at these extremes. |
| **Task conflation** | A high MTEB average covers 8 categories. Your system performs one. A model ranked 40th overall but 2nd on Retrieval is the better choice for retrieval. |
| **Benchmark contamination** | MTEB v1 (56 tasks) is susceptible to training set overlap. MTEB v2 and MMTEB (500+ tasks) were introduced to resist this. |
| **Self-reported scores** | Not independently verified. Model cards may cherry-pick evaluation settings. |

**Rule:** A model ranked 40th overall but 2nd on the task-specific subtab is the right choice for that task. Always filter MTEB by your specific task tab, language, and sequence length.

---

## Three-Pillar Evaluation Framework

### Pillar 1: Intrinsic Evaluation

Measures representational quality in isolation. Fast and cheap. Screening step, not a final decision.

| Method | What it measures | Key metrics |
|---|---|---|
| STS benchmarks (STS-B, SICK-R) | Cosine similarity correlation with human judgments | Spearman rho, Pearson r |
| Nearest-neighbor coherence | Whether k-NN clusters are semantically consistent | Manual inspection, V-measure |
| Isotropy analysis | Whether embeddings are uniformly distributed or collapse into a cone | Partition score, IsoScore |
| Dimension utilization | Number of active dimensions after PCA | Explained variance ratio |

**Limitation:** Intrinsic scores correlate weakly with downstream task performance. Strong STS score does not guarantee strong retrieval.

### Pillar 2: Extrinsic (Downstream Task) Evaluation

Primary decision signal. Measures how well embeddings serve your actual task.

| Task | Evaluation approach | Primary metrics |
|---|---|---|
| Retrieval / RAG | BEIR-style benchmark or custom corpus | nDCG@10, MRR@10, Recall@k |
| Classification | Linear probe or k-NN on labeled sample | Accuracy, F1 (macro/micro) |
| Clustering | K-Means or HDBSCAN on embeddings | V-measure, NMI, ARI |
| STS | Cosine similarity vs. human ratings | Spearman rho |
| Reranking | Cross-encoder vs. bi-encoder scoring | MAP, NDCG |
| QA (RAG) | End-to-end pipeline accuracy | Exact Match, F1, LLM-graded accuracy |

**Critical insight (BES4RAG, ACL 2025):** For RAG tasks, evaluate on QA accuracy (does the LLM answer correctly given retrieved context?), not purely on retrieval metrics. Retrieval nDCG and downstream QA accuracy diverge significantly across datasets. The best retrieval-metric model is not always the best QA-accuracy model.

### Pillar 3: Robustness and Operational Evaluation

Measures production-readiness beyond accuracy.

| Dimension | What to test | Signal |
|---|---|---|
| Domain generalization | Zero-shot on out-of-domain samples | BEIR zero-shot nDCG@10 |
| Adversarial robustness | Paraphrases, typos, lexical variants | Recall drop vs. clean inputs |
| Null/near-null queries | Empty strings, stopword-only queries | Near-zero-norm or random vectors |
| Embedding drift | Cosine distance of re-embedded text across model versions | Similarity score stability |
| Throughput | Queries/second at target latency | P50/P95 at batch sizes 1, 32, 128 |
| Memory footprint | RAM/VRAM at max sequence length | GB per 1M embeddings stored |
| Quantization degradation | Quality loss at int8 and binary precision | nDCG delta vs. float32 |

---

## Task-Specific Evaluation Protocols

### Retrieval / RAG

For retrieval architecture choices (sparse vs. dense vs. hybrid, reranking, chunking), see `retrieval.md`. This section covers evaluating which embedding model to use.

**Protocol:**

1. **Retrieval evaluation:** Build index, retrieve top-k per query, score against relevance judgments. Compute nDCG@10, MRR@10, Recall@100.
2. **End-to-end RAG evaluation:** Generate 50-200 representative questions from your corpus. For each candidate model, retrieve top-k, feed to LLM, score answers as correct/incorrect. Report accuracy per model.
3. **Ablation on k:** Test k = 1, 3, 5, 10. If accuracy saturates at k=1, embedding quality at rank 1 is what matters. If accuracy increases substantially to k=10, you're relying on recall depth.

**Key pitfalls:**

- **Query-document asymmetry.** Use instruction prefixes where supported (e.g., `"Instruct: Retrieve relevant passages\nQuery: {text}"`). Omitting them on instruction-aware models degrades nDCG by 2-8%.
- **Chunk size sensitivity.** Test 128, 256, 512, and 1024-token chunks. Models with 8K+ context can use late chunking (embed full doc, pool per chunk) for better contextual coherence.
- **False negative contamination.** Approximately 70% of naively mined BM25 negatives contain false negatives. Verify "negative" passages are truly irrelevant.

### Classification

**Protocol:**

1. **Linear probe (frozen embeddings):** Embed all samples, train logistic regression, evaluate. Reveals intrinsic classifiability of the embedding space.
2. **k-NN classification (zero/few-shot):** Embed labeled examples, assign by majority vote among k nearest neighbors. Test k = 1, 5, 10, 25.

**Metrics:**
- Balanced datasets: Accuracy
- Imbalanced datasets: Macro F1
- Multi-label: micro-F1, macro-F1
- High-stakes (medical/legal): ROC-AUC, Sensitivity at fixed Specificity

**Key pitfalls:**
- High-dim embeddings (4096) + small training sets (<500) can overfit. Use MRL truncation to 256-512 dims.
- Instruction-aware models need the right instruction (e.g., `"Instruct: Classify the following text by sentiment"`). Jina v3 uses dedicated LoRA adapters per task.

### Clustering

**Protocol:**

1. Embed the full collection. Apply K-Means (known k), HDBSCAN (unknown k), or Agglomerative Clustering.
2. With ground-truth: V-measure, NMI, ARI. Without: Silhouette Score, Davies-Bouldin Index.
3. Visual inspection with UMAP or t-SNE on a 1,000-5,000 sample subset.

| Metric | Range | Interpretation |
|---|---|---|
| V-measure | [0, 1] | Harmonic mean of homogeneity and completeness |
| NMI | [0, 1] | Mutual information normalized by entropy |
| ARI | [-1, 1] | Chance-corrected cluster agreement |
| Silhouette Score | [-1, 1] | Intra-cluster cohesion vs. inter-cluster separation |

**Key pitfalls:**
- **Anisotropy degrades clustering.** Embeddings in a narrow cone make cosine-distance clustering unreliable. Apply whitening or ABTT correction.
- **Dimensionality curse.** >1024 dims hurts clustering. Use MRL truncation to 256-512 dims or PCA.

### Semantic Textual Similarity (STS)

**Protocol:** Embed sentence pairs, compute cosine similarity, calculate Spearman rho against human scores. Flag models with Spearman rho < 0.80 on STS-B.

**Key pitfalls:**
- **Cosine saturation.** Embeddings trained without angular-aware objectives cluster near +/-1, compressing useful variation. Test score distribution histograms.
- **Length bias.** Longer sentences get artificially lower similarity from pooling dilution. Evaluate per length bucket.

### Reranking

See `retrieval.md` for the bi-encoder retrieval -> cross-encoder reranking architecture. For embedding-specific evaluation:

**Decision point:** If nDCG@10 gap between bi-encoder-only and cross-encoder reranking exceeds 3 points on your data, add a cross-encoder (e.g., `cross-encoder/ms-marco-MiniLM-L-12-v2`, Qwen3-Reranker). BGE-M3 supports multi-vector (ColBERT-style MaxSim) scoring as a built-in reranking step at lower latency.

---

## When Embeddings Are Not Enough

Embeddings are the wrong primary tool for these tasks:

| Task | Why embeddings fail | Use instead |
|---|---|---|
| Named entity extraction (span) | Requires token-level prediction, not pooled representation | Fine-tuned token classifier (BERT + CRF) |
| Machine translation | Encodes meaning but cannot decode into target language | Seq2seq model (NLLB, mBART) |
| Exact string matching | Semantic similarity matches "Paris" to "Rome" | BM25, regex, exact match |
| Arithmetic / numerical reasoning | Encodes numerical strings poorly | LLMs with chain-of-thought, structured tools |
| Code generation | Embedding code != generating code | Code LLMs (CodeLlama, Qwen2.5-Coder) |
| Document structure extraction | Layout information lost in text embeddings | Document AI models (LayoutLM, DocFormer) |
| Long-form summarization | Retrieves; does not synthesize | LLMs with long-context support |

**Decision gate:** Ask two questions:
1. Can this task be solved by measuring similarity between vector representations? If yes, embeddings are appropriate.
2. Does this task require generating, transforming, or extracting structured information not in the input? If yes, embeddings alone will fail.

---

## Model Selection Decision Framework

> **Design axiom: Tiered escalation.** Start with the cheapest model that satisfies constraints. Only scale up when evaluation proves it necessary.

### Step 1: Establish Hard Constraints

| Constraint | What it eliminates |
|---|---|
| **Languages:** Non-English only? | English-only models (all-MiniLM, many BERT variants) |
| **Context length:** Documents > 512 tokens? | BERT-family without RoPE extension |
| **Latency:** < 50ms per query? | 7B+ parameter models on CPU |
| **Deployment:** Air-gapped, on-premise? | Commercial API-only models (Gemini Embedding, Cohere) |
| **License:** Commercial use required? | CC-BY-NC-4.0 models (NV-Embed-v2) |
| **Privacy:** Cannot send data externally? | All commercial APIs |
| **GPU VRAM:** < 8 GB? | 7B+ models at fp16 |

### Step 2: Identify Primary Task

From the task-specific evaluation protocols above, locate your task. Note the recommended model families from the Model Reference table below.

### Step 3: Leaderboard Pre-screening

Navigate to the MTEB Hugging Face leaderboard:
- Click the **specific task tab** (Retrieval, Classification, Clustering, etc.)
- Filter by language and sequence length
- MTEB v1 and v2 scores are incomparable -- check which version was used

Shortlist 3-5 candidates that satisfy Step 1 constraints and perform well on the relevant task tab.

### Step 4: Domain Alignment Check

For each shortlisted model:
- Review training data on the model card. Does it include your domain?
- If domain absent: consider domain-specific fine-tunes (MedCPT, Legal-BERT, FinBERT, CodeXEmbed).
- If no domain-specific model exists: test whether a general-purpose model generalizes adequately.

### Step 5: Rapid Empirical Evaluation

```python
# Minimal evaluation harness (retrieval example)
from sentence_transformers import SentenceTransformer
from sklearn.metrics import ndcg_score
import numpy as np

def evaluate_retrieval(model_name, queries, corpus, relevance_labels, k=10):
    model = SentenceTransformer(model_name)
    q_emb = model.encode(queries, normalize_embeddings=True)
    c_emb = model.encode(corpus, normalize_embeddings=True)
    scores = q_emb @ c_emb.T
    return ndcg_score(relevance_labels, scores, k=k)

# Compare candidates on YOUR data
models = ["BAAI/bge-m3", "Alibaba-NLP/gte-Qwen2-7B-instruct", "nvidia/NV-Embed-v2"]
for m in models:
    score = evaluate_retrieval(m, your_queries, your_corpus, your_labels)
    print(f"{m}: nDCG@10 = {score:.4f}")
```

Evaluate all candidates on 100-500 representative samples. Record latency simultaneously.

### Step 6: Efficiency Validation

For the top 2 candidates:
- Test MRL truncation: does 512 dims retain >=97% of full-dim quality?
- Test int8 quantization: does it degrade nDCG by < 1 point?
- Test binary quantization + float32 rescoring: is 32x compression worth the ~3-7% quality delta?
- Measure P95 query latency at target QPS.

### Step 7: Final Selection

Select the model with the best trade-off on: (1) downstream task performance on your data, (2) operational constraints, (3) efficiency at your target serving configuration.

---

## Intrinsic Evaluation Methods

Use these as fast screening before committing to full downstream evaluation.

### Cosine Similarity Distribution Analysis

```python
import numpy as np

embeddings = model.encode(sample_texts, normalize_embeddings=True)
sim_matrix = embeddings @ embeddings.T
upper_triangle = sim_matrix[np.triu_indices_from(sim_matrix, k=1)]

print(f"Mean similarity: {upper_triangle.mean():.3f}")
print(f"Std similarity: {upper_triangle.std():.3f}")
# Healthy: mean 0.1-0.4. Mean > 0.8 = embedding collapse. Mean ~0 with no spread = over-orthogonalized.
```

### Neighborhood Consistency Test

```python
from sklearn.neighbors import NearestNeighbors

nbrs = NearestNeighbors(n_neighbors=11, metric='cosine').fit(embeddings)
distances, indices = nbrs.kneighbors(embeddings)

# Sample 20 texts; print 5 nearest neighbors each
for i in range(min(20, len(sample_texts))):
    print(f"\nQuery: {sample_texts[i][:80]}")
    for j in indices[i][1:6]:
        print(f"  NN: {sample_texts[j][:80]}  (cos_dist={distances[i][list(indices[i]).index(j)]:.3f})")
```

Fastest way to build intuition about whether a model understands your domain.

### Isotropy Score

```python
from scipy.linalg import svd

embeddings_centered = embeddings - embeddings.mean(axis=0)
_, singular_values, _ = svd(embeddings_centered, full_matrices=False)

partition_score = singular_values[-1] / singular_values[0]
# Near 1.0 = isotropic (good). Near 0.0 = collapsed/anisotropic (bad).
print(f"Isotropy (partition score): {partition_score:.4f}")

explained = (singular_values**2 / (singular_values**2).sum()).cumsum()
dims_for_95pct = (explained < 0.95).sum() + 1
print(f"Dims needed for 95% variance: {dims_for_95pct}")
```

---

## Extrinsic Evaluation Methods

### Retrieval: BEIR-Style

```python
from beir.datasets.data_loader import GenericDataLoader
from beir.retrieval.evaluation import EvaluateRetrieval
from beir.retrieval import models
from beir.retrieval.search.dense import DenseRetrievalExactSearch as DRES

corpus, queries, qrels = GenericDataLoader(data_folder=data_path).load(split="test")

model = DRES(models.SentenceBERT("BAAI/bge-large-en-v1.5"), batch_size=256)
retriever = EvaluateRetrieval(model, score_function="dot")
results = retriever.retrieve(corpus, queries)
ndcg, map_, recall, precision = retriever.evaluate(qrels, results, retriever.k_values)
```

### Classification: Linear Probe

```python
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report

X_train = model.encode(train_texts, show_progress_bar=True)
X_test = model.encode(test_texts, show_progress_bar=True)

clf = LogisticRegression(max_iter=1000, C=1.0)
clf.fit(X_train, train_labels)
print(classification_report(test_labels, clf.predict(X_test)))
# Sweep C in [0.01, 0.1, 1.0, 10.0] with 5-fold CV on training set.
```

### Clustering: K-Means + V-measure

```python
from sklearn.cluster import KMeans
from sklearn.metrics import v_measure_score, normalized_mutual_info_score, adjusted_rand_score

embeddings = model.encode(texts)
km = KMeans(n_clusters=len(set(true_labels)), random_state=42, n_init=10)
predicted = km.fit_predict(embeddings)

print(f"V-measure: {v_measure_score(true_labels, predicted):.4f}")
print(f"NMI:       {normalized_mutual_info_score(true_labels, predicted):.4f}")
print(f"ARI:       {adjusted_rand_score(true_labels, predicted):.4f}")
```

For unknown k, use HDBSCAN with `min_cluster_size` sweep (5, 10, 20, 50) and select by Silhouette Score.

---

## Production Readiness Testing

### Throughput Benchmarking

```python
import time

def benchmark_throughput(model, texts, batch_sizes=[1, 16, 32, 64, 128]):
    for bs in batch_sizes:
        batches = [texts[i:i+bs] for i in range(0, min(len(texts), 1000), bs)]
        start = time.perf_counter()
        for batch in batches:
            model.encode(batch, show_progress_bar=False)
        elapsed = time.perf_counter() - start
        print(f"Batch size {bs:4d}: {len(batches) * bs / elapsed:.1f} queries/sec")
```

### Quantization Degradation Test

```python
import numpy as np

full_embeddings = model.encode(eval_texts, normalize_embeddings=True)

# MRL truncation test
for dims in [64, 128, 256, 512]:
    truncated = full_embeddings[:, :dims]
    truncated /= np.linalg.norm(truncated, axis=1, keepdims=True)
    # Compute nDCG on retrieval eval with truncated embeddings
    # Compare against full_embeddings baseline

# Binary quantization
binary = (full_embeddings > 0).astype(np.float32) * 2 - 1
# Hamming similarity via dot product on {-1, +1} vectors
# Rescore top-100 shortlist with original float32 embeddings
```

---

## Efficiency Trade-offs

> **Design axiom: Model costs first.** Calculate storage, latency, and compute costs at expected scale before committing to a model size or precision.

### MRL (Matryoshka) Dimension Reduction

| Dimension | Quality retention | Storage vs. full | Recommended use |
|---|---|---|---|
| Full (3072/4096) | 100% | 1x | Offline indexing, highest accuracy |
| 1024 | ~99% | 0.25-0.33x | Production retrieval, balanced |
| 512 | ~98% | 0.125-0.17x | Standard production default |
| 256 | ~97% | 0.06-0.08x | Cost-sensitive RAG |
| 128 | ~94% | 0.03-0.04x | Real-time / edge scenarios |
| 64 | ~88% | 0.015-0.02x | First-stage retrieval only |

### Quantization Pipeline

Two-stage production approach (binary + rescore):

1. **Index:** Binary (1-bit) embeddings in ANN index (Faiss, Hnswlib).
2. **Retrieve:** Top-100 via Hamming distance (~2 CPU cycles/comparison, 32x storage reduction).
3. **Rescore:** Top-100 with float32 query x int8 stored document embeddings.
4. **Return:** Top-10 to user.

| Configuration | Storage | Latency | Quality |
|---|---|---|---|
| float32 full dims | 1x | 1x | 100% |
| int8 full dims | 0.25x | ~0.7x | ~99% |
| binary full dims | 0.03x | ~0.1x | ~92-93% |
| binary + float32 rescore | ~0.05x | ~0.2x | ~96-97% |
| MRL 512 + int8 | ~0.03x | ~0.15x | ~96% |
| MRL 256 + binary + rescore | ~0.008x | ~0.07x | ~93% |

### Model Size vs. Quality

| Parameter range | Quality tier | Inference speed (GPU) | Recommended for |
|---|---|---|---|
| < 150M | Baseline | Very fast | Edge, real-time, large-scale indexing |
| 150M-500M | Good | Fast | Production with latency constraints |
| 500M-1.5B | Strong | Moderate | Balanced production |
| 1.5B-8B | SOTA | Slow (GPU required) | Offline indexing, quality-first |
| > 8B | Diminishing returns | Very slow | Specialized high-accuracy |

---

## Domain-Specific Considerations

### Biomedical / Clinical

- **Problem:** General models miss biomedical terminology, drug names, clinical abbreviations.
- **Recommended:** PubMedBERT, BioBERT, BioLinkBERT, MedCPT (trained on PubMed + clinical notes).
- **Evaluation datasets:** BEIR-BIOASQ, MedMCQA, MIMIC-III derived corpora.
- **Sanity check:** Embed "MI" -- nearest neighbors should include "myocardial infarction", not "Michigan".

### Legal

- **Problem:** Nested references, citation structures, section hierarchies, jurisdiction-specific language.
- **Recommended:** Legal-BERT, SAILER (case-law), fine-tuned BGE on legal corpora.
- **Evaluation datasets:** LegalBench, MultiLegalPile retrieval tasks.
- **Sanity check:** EU vs. US legal concepts should have low similarity despite shared terminology.

### Financial

- **Problem:** Mixes formal reporting with informal commentary; numerical values as text are poorly handled.
- **Recommended:** FinBERT, BGE Base Financial Matryoshka.
- **Evaluation datasets:** FinMTEB, FIQA.
- **Limitation:** All embedding models struggle with quantitative reasoning. Do not use embeddings alone to match "revenue of $2B" with "twice the $1B baseline". Use structured extraction for numerical tasks.

### Code

- **Problem:** Syntactic structure and cross-language similarity patterns absent from natural language pre-training.
- **Recommended:** CodeBERT, GraphCodeBERT, CodeXEmbed, UniXcoder.
- **Evaluation:** CodeSearchNet (6 languages), AdvTest (adversarial).
- **Sanity check:** Semantically equivalent Python and Java functions should have high cosine similarity.

### Multilingual / Low-Resource

Check coverage before deployment:
1. Confirm tokenizer vocabulary coverage for target script (check OOV rate on sample).
2. Run MIRACL or FLORES retrieval on target language.
3. For < 100K training documents, prefer LaBSE or BGE-M3 over LLM-based embedders.

---

## Benchmarks Reference

| Benchmark | Tasks | Languages | Primary metric | Use for |
|---|---|---|---|---|
| MTEB v1 | 56 tasks, 8 categories | Primarily English | Task-specific | General English screening |
| MTEB v2 | Refreshed, contamination-resistant | English | Task-specific | Current English evaluation |
| MMTEB | 500+ tasks | 250+ languages | Borda count | Multilingual comprehensive |
| BEIR | 18 datasets | English | nDCG@10 | Zero-shot retrieval gold standard |
| BEIR 2.0 | + adversarial, code | English | nDCG@10 | Robustness testing |
| MIRACL | 18 languages | 10 language families | nDCG@10 | Multilingual retrieval |
| LongEmbed | Long-context retrieval | English | nDCG@10 | Documents > 8K tokens |
| AIR-Bench | 9 domains, LLM-generated | 13 languages | nDCG@10 | Domain generalization |
| STS-B | Sentence similarity | English | Spearman rho | STS screening |
| FinMTEB | Financial tasks | English | Task-specific | Finance domain |
| C-MTEB | 35 tasks | Chinese | Task-specific | Chinese language |

**How to read MTEB scores:**

1. The aggregate "average" is a red herring. Always use the task-specific subtab.
2. MTEB v1 and v2 scores are incomparable. Check which version was used.
3. Filter by your exact language and sequence length requirements.

---

## Model Reference by Task

| Task | Best open-weight (quality) | Best open-weight (efficiency) | Best commercial |
|---|---|---|---|
| English retrieval | NV-Embed-v2, BGE-en-ICL | GTE-multilingual-base, BGE-M3 | Gemini Embedding 001 |
| Multilingual retrieval | Qwen3-Embedding-8B | BGE-M3 | Cohere Embed v4 |
| English STS | UAE-Large-V1, mxbai-embed-large | all-mpnet-base-v2 | text-embedding-3-large (OpenAI) |
| Classification | Jina v3 (LoRA), GTE-Qwen2 | GTE-multilingual-base | Cohere Embed v4 |
| Clustering | Qwen3-Embedding, nomic-embed-v2 | GTE-multilingual-base | Gemini Embedding |
| Long documents | Qwen3-Embedding (32K) | BGE-M3 (8K) | Voyage-3-large (32K) |
| Code retrieval | CodeXEmbed, UniXcoder | CodeBERT | Voyage Code 3 |
| Biomedical | MedCPT, BioLinkBERT | BioBERT | Voyage Medical |
| Financial | BGE Base Financial Matryoshka | FinBERT | Voyage Finance |
| Legal | SAILER, fine-tuned BGE | Legal-BERT | Voyage Legal |

---

## Evaluation Checklist

### Pre-evaluation
- [ ] Defined primary NLP task (retrieval, classification, clustering, STS, reranking, QA)
- [ ] Confirmed embeddings are the right tool (see When Embeddings Are Not Enough)
- [ ] Documented hard constraints: language, context length, latency, license, deployment mode
- [ ] Assembled held-out evaluation dataset (minimum 100 samples, ideally 500+)
- [ ] Constructed query/document pairs with relevance labels

### Intrinsic checks
- [ ] Inspected cosine similarity distribution -- no evidence of collapse (mean < 0.8)
- [ ] Verified neighborhood consistency on your domain data
- [ ] Checked isotropy / partition score
- [ ] Confirmed context length sufficient for longest documents

### Extrinsic evaluation
- [ ] Ran task-specific eval with appropriate metric (nDCG@10, macro-F1, V-measure, Spearman rho)
- [ ] Compared at least 3 candidates on your own data
- [ ] Tested with and without instruction prefixes for instruction-aware models
- [ ] Tested end-to-end pipeline metric (QA accuracy for RAG, not just retrieval nDCG)
- [ ] Checked per-domain, per-length, per-class breakdowns

### Efficiency validation
- [ ] Benchmarked P50 and P95 query latency at target QPS
- [ ] Tested MRL truncation: identified minimum dimension retaining >=97% quality
- [ ] Tested quantization degradation: confirmed acceptable quality delta
- [ ] Estimated storage cost at production scale

### Production readiness
- [ ] Verified license compatibility
- [ ] Confirmed null/edge-case input handling
- [ ] Tested on adversarial/out-of-domain samples
- [ ] Defined monitoring strategy for embedding drift
- [ ] Documented versioning plan (model updates require re-indexing)

---

## Failure Modes

| Failure Mode | Symptom | Mitigation |
|---|---|---|
| **Embedding drift** | Retrieval quality degrades over time as corpus grows or domain shifts | Monitor retrieval metrics (nDCG, MRR) weekly; schedule periodic re-embedding with latest model version; version-tag all indexes |
| **Quantization degradation** | Quality drops after int8/binary quantization exceed acceptable threshold | Run quantization degradation test (§Efficiency Trade-offs) before deploying; set quality delta threshold (e.g., <2% nDCG drop) |
| **Domain mismatch** | General-purpose model underperforms on specialized vocabulary (legal, biomedical, code) | Evaluate domain-specific models (§Domain-Specific Considerations); fine-tune or use domain-adapted models; always test on your own data |
| **Dimensionality over-reduction** | MRL truncation too aggressive, losing semantic nuance | Binary search for minimum viable dimension (§MRL Dimension Reduction); retain >=97% of full-dimension quality |
| **Leaderboard-production gap** | Model tops MTEB but underperforms on your task | Never skip empirical evaluation on held-out data (§Step 5); leaderboard rankings are aggregates, not guarantees |
| **Stale index** | New documents not retrievable; deleted documents still returned | Implement incremental indexing pipeline; add index freshness monitoring; schedule re-index for bulk updates |
| **Null/adversarial input** | Empty strings, prompt injections, or garbage text produce unpredictable embeddings | Validate inputs before encoding; test edge cases (§Production Readiness Testing); add input sanitization layer |

---

**See also:** `retrieval.md` for retrieval architecture (sparse/dense/hybrid, reranking, chunking, agentic RAG). `multi-hop-rag.md` for multi-hop query patterns requiring cross-document reasoning. `evals.md` for the full agent evaluation framework including RAGAS. `production.md` for context engineering, cost modeling, and observability. `structured-classification.md` for classification via constrained decoding (alternative to embedding-based classification).
