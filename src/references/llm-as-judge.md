# LLM-as-Judge: Practitioner's Guide

Using LLMs to evaluate AI system outputs at scale. Covers implementation patterns, bias mitigation, calibration, rubric design, agent evaluation, production deployment, frameworks, and anti-patterns.

## Table of Contents

1. [Core Implementation Patterns](#core-implementation-patterns)
2. [Twelve Documented Biases and Mitigations](#twelve-documented-biases-and-how-to-neutralize-them)
3. [Calibration](#calibration-requires-human-ground-truth-and-iterative-refinement)
4. [Rubric Design](#rubric-design-binary-beats-likert-specificity-drives-agreement)
5. [Decomposed Multi-Dimensional Evaluation](#decomposed-multi-dimensional-evaluation)
6. [Judge Model Selection](#judge-model-selection)
7. [Statistical Rigor](#statistical-rigor)
8. [Agent Evaluation](#agent-evaluation)
9. [Production Deployment](#production-deployment)
10. [Frameworks](#frameworks)
11. [Anti-Patterns and Alternatives](#when-llm-as-judge-fails-anti-patterns-and-alternatives)
12. [Research Frontier](#the-research-frontier)
13. [Decision Framework](#decision-framework-for-practitioners)

---

## Core Implementation Patterns

LLM-as-Judge achieves **80% agreement with human evaluators** when done right, matching human-to-human agreement rates. Three fundamental evaluation architectures exist:

**Pointwise scoring** rates a single output on an absolute scale. The workhorse for production monitoring — requires only one judge call per item and resists adversarial manipulation better than alternatives (Tripathi et al. 2025 found pairwise preferences flip in ~35% of adversarial cases versus only 9% for absolute scores).

**Pairwise comparison** presents two outputs side-by-side and asks which is better. Achieves the highest alignment with human preferences in head-to-head model comparisons. GPT-4 achieves ~80% agreement with humans in pairwise mode.

**Reference-guided evaluation** provides a gold-standard answer as an anchor. Dramatically improves consistency for factual QA and regression testing.

**When to use each:**

| Pattern | Best For | When NOT to Use |
|---|---|---|
| Pointwise | Production monitoring, single-output quality gates, high volume | When comparing two specific outputs head-to-head |
| Pairwise | Model comparison, A/B testing, preference tuning | Production monitoring (2x cost), adversarial-prone contexts |
| Reference-guided | Factual QA, regression testing, known-answer evaluation | Creative tasks, open-ended generation without ground truth |

### G-Eval Framework

The most widely adopted chain-of-thought evaluation approach (Liu et al., EMNLP 2023). Three steps: the LLM auto-generates evaluation reasoning steps from your criteria, those steps are concatenated with the original context, and the model scores on a 1-5 scale. The critical innovation is **token probability weighting** — rather than taking the single output token, G-Eval computes a weighted sum across score token probabilities, counteracting the model's tendency to over-select "3" on a 1-5 scale. Achieved Spearman correlation of **0.514** with human judgments on summarization, outperforming BLEU, ROUGE, BERTScore, and all prior automated metrics.

### Non-Negotiable Settings

| Setting | Value | Why |
|---|---|---|
| Temperature | 0 (or minimum) | Even then, outputs are only "mostly deterministic" due to floating-point effects |
| Output format | Structured JSON with reasoning + score fields | Ensures reliable parsing |
| Output ordering | Reasoning BEFORE score | Forces evaluation rationale before number assignment, improves accuracy |
| Few-shot examples | 1-2 minimum | Increases scoring consistency from 65% to **77.5%** |

### Pointwise Evaluation Prompt Skeleton

```
You are evaluating the quality of an AI assistant's response.

[Criteria with anchor descriptions for each score level]

Evaluate the following:
User question: {question}
AI response: {response}

Output your evaluation as JSON:
{"reasoning": "...", "score": <integer>}
```

---

## Twelve Documented Biases and How to Neutralize Them

### Position Bias (most severe)

By simply swapping which response appears first in a pairwise comparison, Vicuna-13B could beat ChatGPT on **66 of 80 queries (82.5%)** when ChatGPT was the judge (Wang et al., ACL 2024). GPT-4 shows approximately **40% inconsistency** when answer order is reversed. Claude-3 models consistently display recency preference (favoring the second position).

**Mitigation:** Run every pairwise comparison twice with swapped positions. Only declare a winner when the same response wins in both orderings. Otherwise, declare a tie.

### Verbosity Bias

Inflates scores by approximately **15%** for longer responses regardless of substantive quality. GPT-3.5 and earlier Claude models both show clear verbosity preference; GPT-4+ is less susceptible.

**Mitigation:** Explicitly instruct the judge to penalize padding, add a separate "conciseness" scoring dimension, use length-normalized scoring.

### Self-Preference Bias

GPT-4 favors its own outputs with a **10% higher win rate** compared to human judgments; earlier Claude models show **~25% self-preference**. Root cause (Wataoka et al., ICLR 2025): LLMs assign higher scores to text with lower perplexity relative to their training distribution. Preference leakage extends to models within the same family, including fine-tuned variants and distilled children (Li et al., ICML 2025 Oral).

**Mitigation:** **Cross-family judging** — if you generate with Claude, judge with GPT or Gemini, and vice versa. This is the only reliable mitigation.

### Authority Bias

Judges defer to fabricated citations. The CALM framework (Ye et al., 2024) demonstrated that adding fake academic references to an inferior answer caused GPT-3.5-Turbo to **flip its judgment** in favor of the wrong answer.

### Additional Biases (CALM Framework)

| Bias | Description | Mitigation |
|---|---|---|
| Leniency | LLM judges skew toward higher scores than humans | Calibrate against human baseline |
| Anchoring | Early dimension scores influence subsequent ones | Evaluate each dimension in a separate LLM call |
| Bandwagon | "90% believe R1 is better" shifts judgment | Strip social proof from evaluation context |
| Sentiment | LLMs penalize angry tone even in superior answers | Instruct judge to focus on content, not tone |
| Refinement-awareness | Informing judge that answer was refined inflates scores | Strip metadata about answer provenance |

---

## Calibration Requires Human Ground Truth and Iterative Refinement

**Skipping calibration is the single most common and damaging mistake** practitioners make. Criteria drift (Shankar et al., UIST 2024) means evaluation criteria evolve as humans review actual outputs, making it impossible to finalize rubrics without examining data first.

### Five-Step Calibration Process

1. **Create stratified sample** of 100-500 examples covering the full quality spectrum, including edge cases. Have domain experts score independently and blind to metadata. Calculate **inter-annotator agreement** using Cohen's kappa (2 annotators) or Fleiss' kappa (3+). If kappa < **0.6**, clarify the rubric before proceeding.
2. **Run LLM judge** on held-out validation set. Measure alignment using both correlation (Pearson, Spearman — target **r >= 0.80**) and agreement metrics (Cohen's kappa). Correlation alone is insufficient: an LLM could achieve perfect correlation while being systematically lenient.
3. **Error analysis** on disagreements. Look for systematic patterns.
4. **Adjust judge prompt** to address failure modes and re-evaluate. One LangChain team improved alignment from **29% to 71%** through systematic prompt refinement.
5. **Validate on held-out test set**, then lock the prompt.

### Recalibration Triggers

- Model API updates (GPT-4 to GPT-4o)
- Production input distribution shifts
- Periodic golden-dataset checks (30-50 human-labeled examples, weekly or monthly)
- Alert when kappa drops below established threshold
- Version-pin API models and re-validate after any version change

---

## Rubric Design: Binary Beats Likert, Specificity Drives Agreement

The single most impactful rubric design decision is **scale granularity**.

### Scale Reliability Hierarchy

| Scale | Reliability | When to Use | When NOT to Use |
|---|---|---|---|
| Binary (pass/fail) | Highest | Production monitoring, CI/CD gates, checklist evaluation | When you need gradation between "acceptable" and "excellent" |
| 3-4 point | Good | Development evaluation, moderate granularity needed | When binary suffices (adds unnecessary complexity) |
| 1-5 with anchors | Acceptable | Development with well-defined anchor descriptions per level | Without anchored descriptions for every score level |
| 1-10 or continuous | Avoid | Almost never | Always — LLMs perform poorly at fine-grained discrimination |

CheckEval (Lee et al., EMNLP 2025): decomposing criteria into binary checklist questions improved inter-evaluator agreement by **+0.45** and average correlation with human judgments by **+0.10** across 12 evaluator models. For full CheckEval implementation patterns, scale selection, and prompt templates, see `binary-evals.md`.

### Anchor Description Example (1-5 Helpfulness)

**Good rubric:**
- Score 5: Directly addresses the question with specific, actionable detail and anticipates follow-up needs.
- Score 4: Mostly addresses the question with good coverage but misses minor details.
- Score 3: Covers basic aspects but lacks depth or specificity.
- Score 2: Partially addresses the question with vague or incomplete information.
- Score 1: Does not address the question or provides inaccurate information.

**Bad rubric:** "Rate 1-10 how good this is" — no anchors, too wide a scale, vague criteria.

### Google Research "Precise Boolean" Approach

Transform complex Likert criteria into granular binary questions:

| Instead of | Ask |
|---|---|
| "Rate fluency 1-5" | "Are all sentences grammatically correct? (Yes/No)" |
| | "Is the text free of spelling errors? (Yes/No)" |
| | "Do sentences flow logically? (Yes/No)" |

---

## Decomposed Multi-Dimensional Evaluation

Strong evidence favors evaluating criteria separately rather than all at once. DeCE framework (Yu et al., EMNLP 2025): decomposed precision/recall scoring achieved **r = 0.78** correlation with expert judgments, compared to **r = 0.35** for pointwise holistic scoring — a **123% improvement**.

### Aggregation Pattern

1. Independently score each criterion (one LLM call per criterion)
2. Normalize to 0-1 (Likert 1-5 becomes 0.0-1.0, binary True/False becomes 1.0/0.0)
3. Multiply by criterion weight
4. Sum for composite score

Start with **equal weights** as baseline, then optimize against human annotations if needed.

### Caveats

- Some dimensions are task-dependent or correlated with spurious features (Tian et al., 2026)
- Test dimension combinations against your specific task
- Most production systems use **3-7 dimensions**, with 2-3 critical dimensions as starting point
- Alignment and agreement dimensions were "strongly negative on QA but became weakly positive on summarization"

---

## Judge Model Selection

| Model | Strengths | Weaknesses |
|---|---|---|
| GPT-4 | >80% human agreement, strict on math/coding errors | Higher self-preference bias |
| Claude | Lowest self-preference bias (~25.6%) | More lenient overall |
| PoLL (panel of diverse models) | Better than single GPT-4 at **7x lower cost** | Requires multi-model orchestration |
| Prometheus 2 (7B/8x7B) | r=0.6-0.7 with GPT-4, 72-85% human agreement, 16GB VRAM | Biased toward superficial quality (formality, verbosity) |
| GPT-4o-mini | $1.01 per 1,000 evaluations (78x cost reduction) | Lower accuracy on complex semantic evaluation |

### Panel of LLM Evaluators (PoLL)

Multiple smaller models from **different model families** (e.g., Command R + GPT-3.5 + Haiku) outperformed a single GPT-4 judge while being **over 7x cheaper** (Verga et al., 2024). Key requirement is model diversity — same-family panels degrade performance.

**When to use PoLL:** Production evaluation at scale, bias-critical applications, cost-sensitive deployments.

**When NOT to use PoLL:** Low-volume evaluation where single frontier model is affordable, latency-critical synchronous evaluation.

### Tiered Evaluation Architecture

1. Deterministic checks first (free)
2. Cheap models for basic screening
3. Frontier judges only for complex semantic evaluation on flagged items

---

## Statistical Rigor

### Repetitions and Averaging

- **3-5 runs** per evaluation for most use cases, averaging question-level scores
- Increase repetitions until within-question variance becomes negligible relative to between-question variance
- For binary evaluations with token probabilities available, use probabilities directly — **eliminates variance entirely**
- Multi-judge panels (3-5 different models with majority vote): bias reduction of **30-40%** at 3-5x cost

### Confidence Intervals

Use CLT formula (95% CI = x_bar +/- 1.96 x SE) with one critical caveat: **clustered standard errors**. When questions are non-independent (e.g., multiple questions per document), the clustered standard error can be **over 3x larger** than the naive estimate (Anthropic, 2024). Use bootstrap resampling (1,000-10,000 iterations) when CLT assumptions are questionable.

### Paired-Difference Analysis

For comparing two systems: compute d_i = score_A(i) - score_B(i) for each question, then calculate the mean difference and its standard error. Eliminates question-difficulty variance, producing much tighter confidence intervals than unpaired comparison. Detecting an effect **half the size requires 4x the samples** (quadratic relationship).

### Inter-Rater Reliability Metrics

| Metric | Use Case |
|---|---|
| Cohen's kappa | Single LLM judge vs human consensus |
| Fleiss' kappa | Agreement among a judge panel |
| ICC (intraclass correlation) | Continuous scales |

Always combine correlation metrics with agreement metrics — an LLM could have perfect Pearson correlation while being systematically 2 points too lenient.

---

## Agent Evaluation

Agent evaluation requires moving beyond single-output assessment to three levels:

| Level | What It Examines | Strengths | Weaknesses |
|---|---|---|---|
| Final response (black-box) | End result only | Simple, fast | Misses "silent failures" where answer is correct but reasoning was wrong |
| Trajectory (glass-box) | Full sequence of tool calls and reasoning | Catches process errors | Long context, alternative valid paths make exact matching brittle |
| Single-step (white-box) | Each individual decision | Precise error localization | High evaluation cost per decision |

### Agent-as-a-Judge (Zhuge et al., ICLR 2025)

Uses an agentic system (not just a single LLM call) to evaluate another agent. The judge agent can re-execute code, check intermediate artifacts, verify tool outputs, and trace the full reasoning chain. On DevAI benchmark (55 realistic AI development tasks), Agent-as-a-Judge disagreed with human-majority vote only **0.3% of the time**, versus a standard LLM judge disagreeing **31% of the time**.

**When to use:** Complex agent tasks with code execution, multi-step tool use, verifiable intermediate artifacts.

**When NOT to use:** Simple single-turn evaluations, cost-constrained environments (judge agent is expensive).

### Key Trajectory Metrics

- **Convergence**: fraction reaching satisfactory terminal state
- **Optimal path ratio**: actual steps / best-known steps
- **Loop detection**: frequency of unproductive cycles

### Tool Use Evaluation (DeepEval)

Three levels of strictness:
1. Tool selection (correct tools chosen)
2. Input parameters (correct arguments passed)
3. Output accuracy (results match expectations)

---

## Production Deployment

### Cost Optimization (stack multiplicatively)

| Strategy | Savings | Details |
|---|---|---|
| Prompt caching | ~90% on rubric tokens | System prompt is identical across evaluations |
| Batch APIs | ~50% discount | 24-hour turnaround acceptable |
| Tiered evaluation | Variable | Route only flagged items to frontier judges |
| Semantic caching | ~35% on near-duplicates | Cache evaluations for semantically similar inputs |
| Combined | **70-95% total** | |

### Production Pipeline Architecture

1. **Trace collection** — log all LLM interactions with full metadata
2. **Sampling layer** — select 1-10% of traffic for evaluation (stratified by risk indicators)
3. **Deterministic pre-filter** — regex, JSON validation, format checks (free, instant)
4. **Budget model screen** — GPT-4o-mini or equivalent for basic quality classification
5. **Frontier judge** — GPT-4/Claude for complex semantic evaluation on flagged items only
6. **Score aggregation** — store scores, compute trends, track distributions
7. **Alerting** — anomaly detection triggers when quality metrics degrade
8. **Feedback loop** — low-quality traces route to human review and golden dataset updates

### Online vs Offline Evaluation

**Online evaluation** scores live production traces asynchronously without adding user-facing latency. **Offline evaluation** tests against curated datasets before deployment. Run offline experiments on every prompt change, model swap, or retrieval modification before deployment. Real-world edge cases discovered online feed back into the offline dataset.

### Judge Distillation

Organizations regularly achieve **50-85% cost reductions** by training smaller student models to replicate frontier judge behavior. A 7B-parameter model fine-tuned on GPT-4 evaluation outputs can achieve ~90% of the quality. Highest-ROI for well-defined, high-volume evaluation tasks.

---

## Frameworks

| Framework | Strengths | Best For |
|---|---|---|
| **DeepEval** | 50+ LLM-as-judge metrics, Pytest-style CI/CD integration | Comprehensive evaluation-first workflows |
| **RAGAS** | Faithfulness, context recall/precision, factual correctness | RAG-specific evaluation |
| **Langfuse** | Open-source observability + evaluation, self-hostable | Production monitoring with built-in judges |
| **Braintrust** | End-to-end platform, GitHub Action quality gates | Teams needing eval-driven CI/CD (used by Perplexity, Notion, Stripe) |
| **promptfoo** | Declarative YAML config, fully open-source, runs locally | Developer-friendly model comparison and red-teaming |
| **Inspect AI** | 100+ benchmarks, sandboxed execution, agent evaluation | Frontier model safety evaluation (adopted by Anthropic, DeepMind) |

### DeepEval Example

```python
from deepeval.metrics import GEval
from deepeval.test_case import LLMTestCase, LLMTestCaseParams

correctness = GEval(
    name="Correctness",
    criteria="Determine whether the actual output is factually correct based on the expected output.",
    evaluation_params=[
        LLMTestCaseParams.INPUT,
        LLMTestCaseParams.ACTUAL_OUTPUT,
        LLMTestCaseParams.EXPECTED_OUTPUT,
    ],
)
```

---

## When LLM-as-Judge Fails: Anti-Patterns and Alternatives

| Anti-Pattern | Why It Fails | Use Instead |
|---|---|---|
| LLM judge for deterministic checks (JSON format, length, required fields) | Free, instant, perfectly reliable alternatives exist | Code-based validation (regex, schema validation) |
| LLM judge for math/code correctness | Judges consistently underperform solvers (JudgeBench, ICLR 2025) | Execute code and check outputs deterministically |
| Same model family for generation and evaluation | Preference leakage extends to fine-tuned variants and distilled children (ICML 2025) | Cross-family judging |
| LLM judge for factual accuracy without references | Judges hallucinate when assessing factual claims without provided context | Reference-based evaluation or retrieval-augmented verification |
| Trusting LLM judge scores as precise measurements | Style-over-substance bias (SOS-Bench, ICLR): judge preferences do not correlate with safety, knowledge, instruction following | Treat as noisy signals, calibrate with human baselines |
| Using LLM-as-judge during RL training with same model | Generator discovers responses that increase evaluator reward while actual accuracy drops (RLME) | Cross-model evaluation, human-in-the-loop |

### The "Style Outweighs Substance" Problem

LLM-judge preferences **do not correlate** with concrete measures of safety, world knowledge, and instruction following (SOS-Bench, ICLR). Judges have powerful implicit biases **prioritizing style over factuality and safety**. LLM judges are excellent for subjective quality assessment (helpfulness, tone, coherence) but unreliable as the sole arbiter of correctness.

### Evaluator Hacking

RobustJudge (2025): adversaries can inject instructions into responses to manipulate judge scores. RLME research: during RL training with same-model evaluation, "the generator discovers responses that cause the evaluator to answer meta-questions in a way that increases reward" while actual accuracy drops.

---

## The Research Frontier

### TIR-Judge (2025-2026)

Gives judges the ability to execute code and call tools during evaluation. An 8B-parameter TIR-Judge achieves performance comparable to Claude Opus on listwise tasks, with **4.8-9.9% improvement** over baselines on pointwise evaluation.

### SAGE (Feng et al., December 2025)

Annotation-free judge meta-evaluation using rational choice theory axioms. Even top-performing models fail to maintain consistent preferences in **~25% of difficult cases**. Also discovered substantial inconsistency in human judgments, questioning the gold-standard assumption.

### Multi-Agent Judging Panels

ChatEval (ICLR 2024): multi-agent debate achieves Kendall Tau 0.57 with humans versus 0.52 for single GPT-4. MAJ-Eval (2025): outperformed both ChatEval and G-Eval on domain-specific tasks through stakeholder-persona-based intra-group debates. Practical implementations report **8-15% reliability gains**.

### Cross-Organization Evaluation

2025 OpenAI-Anthropic joint safety evaluation: each company ran the other's internal safety evaluations on publicly released models. Signals maturation of evaluation ecosystem and reinforces importance of cross-model judging.

---

## Decision Framework for Practitioners

### Core Checklist

1. **Calibrate** with 100-500 human-labeled examples
2. **Use binary scales** (decompose complex criteria into yes/no questions)
3. **Evaluate one criterion per call** (decomposed > holistic)
4. **Judge with a different model family** than you generate with
5. **Run position-switched pairwise comparisons** (both orderings)
6. **Calculate clustered confidence intervals** (not naive SE)
7. **Monitor for drift** (weekly golden-dataset checks)

### Three Non-Obvious Insights

1. **Binary decomposition beats sophisticated scoring**: CheckEval's simple yes/no checklist items improved agreement by +0.45 over Likert scales. The urge to use 1-10 scales for nuance actually destroys signal. See `binary-evals.md` for the full implementation guide.
2. **The cheapest approach is often the best**: a panel of three diverse budget models (PoLL) outperforms a single frontier judge at 7x lower cost.
3. **The biggest risk is not inaccuracy but false confidence**: clustered standard errors are 3x larger than naive estimates, style-over-substance bias systematically misleads, and even top models fail 25% of hard cases.
