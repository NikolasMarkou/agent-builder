# Binary Rules for LLM-as-Judge

Binary decomposition — breaking evaluation criteria into yes/no checklist questions — is the single highest-leverage change you can make to your LLM evaluation pipeline. It improves inter-evaluator agreement by +0.45, improves correlation with human judgments by +0.10, cuts evaluation time by 50%+, and produces interpretable, traceable scores.

This is a deep-dive companion to `llm-as-judge.md`. Read that file first for the broader LLM-as-Judge landscape (implementation patterns, bias mitigation, calibration, judge model selection, agent evaluation, production deployment).

## Table of Contents

1. [Why Binary Beats Scales](#why-binary-beats-scales)
2. [The CheckEval Framework](#the-checkeval-framework)
3. [Google's Adaptive Precise Boolean Approach](#googles-adaptive-precise-boolean-approach)
4. [Implementation Patterns](#practical-implementation-patterns)
5. [Scale Selection Decision Tree](#scale-selection-decision-tree)
6. [Prompt Engineering for Binary Judges](#prompt-engineering-for-binary-judges)
7. [Computing Composite Scores](#computing-composite-scores-from-binary-checklists)
8. [Calibration](#calibration-with-binary-judges)
9. [When NOT to Use Binary](#when-not-to-use-binary)
10. [Framework Support](#framework-support)
11. [References](#references)

---

## Why Binary Beats Scales

LLMs are poorly calibrated on arbitrary numeric scales. A response that gets a "7" from one run might get a "5" from the next. Humans disagree on whether something is a 6 or 7. The ambiguity compounds.

Binary questions eliminate this. "Does the response contain factual errors? Yes/No" has a clear answer. The judge doesn't need to decide *how good* something is on a continuum — it classifies.

**Evidence:**

- **CheckEval** (Lee et al., EMNLP 2025): Decomposed binary questions improved average inter-evaluator agreement by **+0.45** across 12 evaluator models and multiple datasets. Score variance dropped substantially.
- **Google Research Adaptive Precise Boolean rubrics** (2025): Boolean rubrics showed "clear, positive correlation" with quality improvements while Likert scales showed "limited sensitivity." Evaluation time dropped 50%+ compared to Likert.
- **Arize AI** (2025): Testing with GPT-4o-mini, Claude Opus, and Qwen3 confirmed "numeric scoring can flag major differences but breaks down for finer judgments" — scores produce plateaus, discontinuous jumps, and bimodal distributions.
- **Confident AI / DeepEval**: LLMs can be reliable judges for binary factual correctness, but as scoring scales become more detailed, they produce arbitrary scores with more randomness.

---

## The CheckEval Framework

The reference implementation for binary evaluation. Three stages:

**Stage 1: Define evaluation dimensions.** Select the high-level quality dimensions relevant to your task (accuracy, relevance, coherence, etc.) and define sub-dimensions within each.

**Stage 2: Generate checklist questions.** Each sub-dimension becomes one or more binary yes/no questions. Two augmentation techniques improve coverage:
- **Question diversification** — generating multiple phrasings of the same criterion
- **Elaboration** — adding specificity to vague criteria

**Stage 3: Evaluate.** The LLM judge answers each checklist question independently with "Yes" or "No." The final score for each dimension is the proportion of "Yes" answers.

### Example Transformation

Instead of: "Rate the coherence of this summary on a 1-5 scale."

CheckEval produces:
- Does the summary follow a logical structure? (Yes/No)
- Are there any contradictions between sentences? (Yes/No)
- Does each sentence connect naturally to the next? (Yes/No)
- Is the main argument clear throughout? (Yes/No)

Score = proportion of "Yes" answers (e.g., 3/4 = 0.75)

This score is interpretable. You know *why* it scored 0.75 — because it had a contradiction. A Likert "3" tells you nothing about what went wrong.

**When to use:** Any evaluation task where you need interpretable, traceable scores with high inter-evaluator agreement.

**When NOT to use:** Tasks where the evaluation criteria genuinely resist binary decomposition (e.g., creative writing style, aesthetic quality).

---

## Google's Adaptive Precise Boolean Approach

Google Research independently arrived at the same conclusion for healthcare LLM evaluation:

1. Start with existing Likert-scale rubrics
2. Iteratively transform each complex criterion into granular boolean (Yes/No) questions
3. Use an LLM (Gemini) as a zero-shot classifier to filter out irrelevant questions per (query, response) pair
4. Evaluate only the relevant subset

The "adaptive" part is key for efficiency. A full boolean rubric can have dozens of questions, but for any given response, only a subset is relevant. The auto-classifier achieved accuracy of 0.77 and F1 of 0.83 for relevance filtering, performing comparably to human-curated filtering.

Result: Higher inter-rater reliability (ICC) than Likert, 50%+ faster than Likert, and more sensitive to subtle quality differences.

**When to use:** Large rubrics with many criteria where not all apply to every response. Domain-specific evaluation (healthcare, legal) where criteria sets are extensive.

**When NOT to use:** Small rubrics where all criteria always apply (the relevance filtering adds unnecessary overhead).

---

## Practical Implementation Patterns

### Pattern 1: Direct Binary Classification

The simplest form. One question, one criterion.

```
You are evaluating an AI assistant's response.

Question: {question}
Response: {response}

Does the response directly answer the user's question?
Reply with only "Yes" or "No".
```

**When to use:** Safety checks, format compliance, factual correctness, policy adherence.

**When NOT to use:** Complex quality assessment requiring multiple facets.

### Pattern 2: Question-Answer Generation (QAG)

Decompose the output into atomic units, then classify each one.

```
Step 1: Extract all factual claims from the response.
Step 2: For each claim, determine: Is this claim supported by the provided context? (Yes/No)
Step 3: Score = (number of supported claims) / (total claims)
```

This is how DeepEval computes faithfulness and answer relevancy. It eliminates arbitrary scoring by grounding the metric in countable, verifiable sub-judgments.

**When to use:** Faithfulness evaluation, hallucination detection, factual accuracy with reference context.

**When NOT to use:** Subjective quality dimensions that can't be decomposed into verifiable claims.

### Pattern 3: Multi-Criterion Checklist (CheckEval Style)

For complex evaluation, decompose into dimensions, then into binary questions.

```json
{
  "accuracy": [
    "Does the response correctly state the main fact requested?",
    "Are all numerical values accurate?",
    "Are there any factual errors or hallucinations?"
  ],
  "completeness": [
    "Does the response address all parts of the user's question?",
    "Are key details included rather than omitted?",
    "Would a user need to ask a follow-up to get the full answer?"
  ],
  "safety": [
    "Does the response avoid providing harmful instructions?",
    "Does the response refrain from revealing PII?",
    "Is the tone appropriate and non-offensive?"
  ]
}
```

Each question is evaluated independently. Dimension score = proportion of "Yes" for positive-framed questions (invert for negative-framed ones like "Are there any factual errors?"). Overall score = weighted average of dimension scores.

**When to use:** Comprehensive evaluation with multiple quality dimensions, production monitoring dashboards.

**When NOT to use:** Quick pass/fail checks where a single binary question suffices.

### Pattern 4: Normalized Scoring for Lightweight Models

RocketEval (ICLR 2025) showed that raw binary outputs from small LLMs have high uncertainty. Instead of taking the literal "Yes"/"No" token, use **token log-probabilities** to compute a continuous confidence score:

```
normalized_score = P("Yes") / (P("Yes") + P("No"))
```

This converts noisy binary outputs into calibrated continuous scores and mitigates positional bias in smaller models.

**When to use:** Small/budget LLMs as judges, high-volume evaluation where confidence calibration matters.

**When NOT to use:** Frontier models where direct Yes/No classification is already reliable.

---

## Scale Selection Decision Tree

| Scale | Use When | Do NOT Use When |
|---|---|---|
| **Binary (Yes/No)** | Factual correctness, policy compliance, safety, format adherence, any criterion with a clear objective threshold | Genuinely continuous quality (creativity, style) |
| **Ternary (Yes/Partial/No)** | Completeness, faithfulness — where partial success is meaningful | Binary would capture the distinction adequately |
| **3-4 point ordinal** | Quality dimensions with meaningful intermediate levels where you can write distinct anchor descriptions | You can't write distinct anchors for each level |
| **5-point Likert** | Genuinely subjective criteria (helpfulness, naturalness) with well-defined anchors for ALL five levels + few-shot examples | Without anchors and examples (accept higher variance) |
| **1-10 or continuous** | **Avoid entirely** | Always — LLMs cannot discriminate reliably at this granularity |

---

## Prompt Engineering for Binary Judges

### Rules

1. **One question per LLM call.** Evaluating multiple criteria simultaneously causes anchoring bias (the first score influences subsequent ones). CheckEval evaluates each question independently.

2. **Reasoning before verdict.** Always require the judge to explain its reasoning before outputting Yes/No. This forces deliberation and enables auditing.

3. **Explicit handling of uncertainty.** Add: "If you cannot determine the answer with reasonable confidence, output 'Unknown'." Route unknowns to human review.

4. **Structured JSON output.**
```json
{"reasoning": "The response states the population is 8.3 million, which matches the reference data.", "answer": "Yes"}
```

5. **Temperature = 0.** Maximum determinism. Even at 0, LLM APIs can produce slight variation due to floating-point effects, so run 3-5 trials for critical evaluations.

6. **Few-shot examples.** Include 1-2 examples showing a "Yes" case and a "No" case with reasoning. This alone improves consistency from ~65% to ~77.5%.

### Template

```
You are an impartial evaluator. Your task is to answer one specific question about an AI assistant's response.

Context:
User question: {question}
AI response: {response}
Reference answer (if available): {reference}

Evaluation question: {checklist_question}

First, explain your reasoning in 2-3 sentences. Then answer "Yes" or "No".

Output as JSON:
{"reasoning": "...", "answer": "Yes" or "No"}
```

---

## Computing Composite Scores from Binary Checklists

### Simple Proportion (default)

```python
dimension_score = sum(1 for q in questions if q.answer == "Yes") / len(questions)
```

Works well when all questions within a dimension are equally important.

### Weighted Proportion

When some questions matter more:

```python
weighted_score = sum(w * (1 if q.answer == "Yes" else 0)
                     for w, q in zip(weights, questions)) / sum(weights)
```

Start with equal weights. Only introduce weighting when you have human-labeled data showing certain questions are more predictive of overall quality.

### Overall Score

```python
overall = sum(dim_weight * dim_score for dim_weight, dim_score in zip(dim_weights, dim_scores))
```

Start with equal dimension weights. Optimize against human annotations if needed. Test dimension combinations against your specific task — some dimensions may be negatively correlated with quality in certain contexts.

---

## Calibration with Binary Judges

Binary classification makes calibration simpler and more rigorous than Likert calibration.

1. **Create a labeled dataset.** 100-500 examples, human-labeled for each binary criterion. Include clear Yes cases, clear No cases, and borderline cases.

2. **Run the judge.** Evaluate each example on each checklist question.

3. **Compute classification metrics per question:**
   - Precision: Of the "Yes" predictions, how many are correct?
   - Recall: Of the actual "Yes" cases, how many did the judge catch?
   - F1: Harmonic mean of precision and recall
   - Cohen's kappa: Agreement adjusted for chance (target >= 0.7)

4. **Identify failure patterns.** Are there specific question types where the judge underperforms? Rewrite those questions, add examples, or route to human review.

5. **Iterate.** Adjust prompts, re-run, compare. Lock the prompt when performance meets your threshold on a held-out test set.

6. **Monitor for drift.** Maintain a static set of 30-50 labeled examples. Re-evaluate weekly/monthly. Alert when kappa drops below threshold or after model API version changes.

Binary judges have a major advantage here: you can use standard classification metrics (precision, recall, F1, confusion matrices) rather than the more ambiguous correlation metrics required for Likert scales.

---

## When NOT to Use Binary

- **Ranking or comparison tasks.** If you need to rank 5 responses, binary per-criterion scoring + composite score works, but pairwise comparison may be more natural.
- **Genuinely continuous quality.** Writing style, creativity, and tone may resist clean binary decomposition. Use ternary or 3-point scales for these.
- **When you need a single holistic judgment.** Some stakeholders want one number. Compute it as a composite from binary sub-scores, but don't ask the LLM to produce it directly.

---

## Framework Support

| Framework | Binary Support |
|---|---|
| **DeepEval** | G-Eval metric with binary thresholds. QAG-based metrics (faithfulness, answer relevancy) use binary decomposition natively. |
| **promptfoo** | `llm-rubric` assertion type returns a boolean `pass` field by default. Supports threshold-based scoring. |
| **Langfuse** | Built-in evaluator templates for binary classification (Hallucination: Yes/No, Toxicity: Yes/No, Helpfulness: Yes/No). Custom evaluators support binary output schemas. |
| **Braintrust** | `LLMClassifier` with choice-to-score mapping supports binary classification. `autoevals` library includes binary-output scorers. |
| **Databricks MLflow** | Guidelines judges return binary pass/fail with detailed rationale. Natural language rules define pass/fail conditions directly. |

---

## References

- Lee, Y., et al. (2025). CheckEval: A reliable LLM-as-a-Judge framework using checklists. *EMNLP 2025*.
- Google Research. (2025). A Scalable Framework for Evaluating Health Language Models (Adaptive Precise Boolean Rubrics).
- Arize AI. (2025). Testing Binary vs Score Evals on the Latest Models.
- Confident AI / DeepEval. (2025). LLM-as-a-Judge Simply Explained.
- RocketEval. (ICLR 2025). Lightweight LLM evaluation via checklist grading with normalized scoring.
- promptfoo. LLM Rubric documentation.
- Langfuse. LLM-as-a-Judge Evaluation: Complete Guide.
- Braintrust. What is an LLM-as-a-judge?
- Databricks. Create a guidelines LLM judge.
