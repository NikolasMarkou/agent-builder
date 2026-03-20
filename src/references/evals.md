# Evaluation Reference

Comprehensive guide to evaluating AI agents in production. Covers evaluation frameworks, benchmarks, metrics, grading methods, safety evaluation, monitoring, tooling, and building eval pipelines.

For a quick evaluation checklist in the production hardening context, see the Evaluation Strategy section in `production.md`. For LLM-as-judge implementation details (biases, calibration, rubric design, production deployment), see `llm-as-judge.md`. For binary evaluation rubric design (CheckEval, boolean decomposition, scale selection), see `binary-evals.md`. This file is the deep-dive reference.

## Table of Contents

1. [Evaluation Frameworks](#evaluation-frameworks)
2. [Benchmarks](#benchmarks)
3. [Metrics](#metrics)
4. [Multi-Step and Multi-Agent Evaluation](#multi-step-and-multi-agent-evaluation)
5. [LLM-as-Judge](#llm-as-judge)
6. [Human Evaluation](#human-evaluation)
7. [Safety Evaluation](#safety-evaluation)
8. [Production Monitoring](#production-monitoring)
9. [Building an Eval Pipeline](#building-an-eval-pipeline)
10. [Best Practices and Anti-Patterns](#best-practices-and-anti-patterns)

---

## Evaluation Frameworks

Three complementary frameworks have emerged as practitioner standards.

### Anthropic's Three-Grader Framework

| Grader Type | Characteristics | Best For |
|---|---|---|
| **Code-based** | Deterministic tests, static analysis, tool call verification | Fast, cheap, reproducible checks — exact match, regex, JSON schema |
| **Model-based** | LLM-as-judge with rubrics | Flexible, scalable — captures nuance in open-ended outputs |
| **Human** | Gold standard quality, expensive, slow | Calibration, safety-critical decisions, novel tasks |

**When to use:** Start every eval suite with code-based graders. Layer model-based graders for subjective criteria. Reserve human graders for calibration and edge cases.

> **Design axioms: Tiered escalation + Decompose.** This cheap-first, expensive-last grading hierarchy mirrors the same architecture used in entity resolution matching (`entity-resolution.md`), search stacks (`text-tools.md`), and LLM-as-judge pipelines (`llm-as-judge.md`). Decompose scoring into binary questions for +0.45 inter-evaluator agreement (`binary-evals.md`).

### Capability vs Regression Evals

| Type | Starting Pass Rate | Purpose | Graduation |
|---|---|---|---|
| **Capability evals** | Low (push boundaries) | Discover what the agent can do | High-passing capability evals graduate to regression suite |
| **Regression evals** | Near 100% (catch backsliding) | Ensure it still works after changes | Never graduate out — expand over time |

**When to use:** Run capability evals during development to push boundaries. Run regression evals in CI/CD to catch regressions.

### Google Cloud's Three Pillars

1. **Agent success and quality** — end-result metrics (task completion, output quality)
2. **Process and trajectory** — reasoning quality, tool selection, step efficiency
3. **Trust and safety** — robustness, prompt injection resistance, bias

**Key insight:** Evaluating only final outputs is insufficient. Trajectory and process matter as much as outcomes. A correct answer reached through incorrect reasoning will eventually fail.

### Galileo's Three-Level Evaluation

| Level | Evaluates | Example |
|---|---|---|
| **Session-level** | Overall goal achievement | "Was the ticket resolved?" |
| **Trace-level** | Individual workflow execution quality | "Were unnecessary steps taken?" |
| **Span-level** | Granular operation success/failure | "Did this API call succeed or silently fail?" |

---

## Benchmarks

### Benchmark Selection by Domain

| Domain | Benchmark | Tasks | Best Score | Human Baseline | Key Limitation |
|---|---|---|---|---|---|
| **Coding** | SWE-bench Verified | 500 GitHub issues | ~81% | ~100% | 12–22% of "passes" are logically wrong |
| **Coding** | SWE-bench Pro | 1,865 tasks / 41 repos | ~23% | — | GPL code as contamination deterrent |
| **Web** | WebArena | 812 tasks | ~62% | ~78% | Self-hosted sites required |
| **Web** | WebChoreArena | 532 long-horizon | ~38% | — | Memory and calculation emphasis |
| **OS** | OSWorld | VM-based tasks | ~38% | ~72% | Requires provisioning VMs |
| **General** | GAIA | 466 multi-step questions | ~75% | ~92% | Growing data contamination |
| **Reliability** | τ-bench | Customer service sims | <50% pass^1 | — | Exposes consistency gaps |
| **Safety** | Cybench | CTF challenges | — | — | Adopted by US/UK AI Safety Institutes |
| **ML Engineering** | MLE-bench | 75 Kaggle competitions | ~17% | — | Low ceiling even for best agents |

### Systemic Benchmark Problems

| Problem | Impact | Mitigation |
|---|---|---|
| **Data contamination** | Up to 76% accuracy via memorization alone on some subtasks | Use fresh/rotating benchmarks (SWE-bench Live), GPL code |
| **Saturation** | HumanEval ~99%, MBPP ~94%, GSM8K >95% — useless for differentiation | Move to harder benchmarks (SWE-bench Pro, OSWorld) |
| **Scaffold confounding** | Benchmarks evaluate harness + model jointly; custom harness = +10 points | Report scaffold details; compare same-scaffold results |
| **Cost/reproducibility** | Full OSWorld requires VMs; few benchmarks track token cost | Track and report API costs alongside scores |
| **Safety gaps** | Safety evaluation severely underrepresented | Supplement with dedicated safety benchmarks |

**When to use benchmarks:** For comparing models/architectures on standardized tasks. NOT as a substitute for domain-specific evals on your actual use case.

**When NOT to use:** As sole evaluation — benchmark performance does not predict production performance. Always build domain-specific evals from real user interactions first.

---

## Metrics

### Core Outcome Metrics

| Metric | What It Measures | Variant |
|---|---|---|
| **Task completion rate** | Does the agent finish the job? | Milestone-based partial credit, graded 0–1 continuous |
| **pass@k** | Can it ever succeed? (≥1 of k trials) | For capability measurement |
| **pass^k** | Does it always succeed? (all k trials) | For production reliability — more informative than pass@k |

### Process and Efficiency Metrics

| Metric | What It Measures | Threshold |
|---|---|---|
| **Trajectory efficiency** | Actual steps / optimal steps | Closer to 1.0 = better |
| **Action Advancement** | Does each action make meaningful progress? | >0.7 = clear progress, <0.3 = spinning |
| **Tool use accuracy** | Correct tool + correct params + correct sequence | Track selection, population, and sequence separately |
| **Turn count per task** | Efficiency | Lower is usually better |

### Cost and Latency Metrics

| Metric | Formula / Target |
|---|---|
| **Token cost per task** | (input_tokens × input_price) + (output_tokens × output_price) across all LLM calls |
| **Cost per successful completion** | Total cost / successful completions |
| **Latency targets** | Simple tasks: <1s, Complex workflows: 2–4s, Voice: <800ms |

**Warning:** One company's PoC cost $500/month; production scale reached $847,000/month — a 717× increase. Model costs before building.

### Safety and Quality Metrics

| Metric | Why It Matters |
|---|---|
| **Hallucination rate** | Compounds in multi-step agents — hallucinated fact in step 2 propagates through all subsequent steps |
| **Faithfulness score** | Logical consistency across reasoning process |
| **Tool misuse rate** | Critical for regulated deployments |
| **Policy adherence rate** | Compliance with defined rules and constraints |
| **PII detection** | Required for any system handling user data |

### Production vs Research Priority Differences

| Dimension | Production Priority | Research Priority |
|---|---|---|
| **Primary metric** | Business outcomes (resolution rate, containment) | Benchmark success rates |
| **Cost** | Hard constraint, must model | Usually secondary |
| **Latency** | SLA-bound | Usually secondary |
| **Safety** | Blocking requirement | Often optional |
| **Satisfaction** | CSAT, NPS tracked | Rarely measured |

---

## Multi-Step and Multi-Agent Evaluation

### The Compounding Error Problem

If each step has 90% success rate:
- 5-step workflow → **59%** end-to-end success
- 10-step workflow → **35%** end-to-end success
- Even 1% per-token error rate → 87% chance of error by token 200

**Implication:** Evaluate end-to-end workflows, not just individual steps. pass^k reveals reliability gaps invisible to single-run evaluation.

### Credit Assignment

When a multi-step workflow fails, identifying which step caused the failure is extremely difficult. Current approaches:

| Approach | Method | Limitation |
|---|---|---|
| **AgenTracer** | Specialized models for multi-granular failure attribution | Outperforms general LLMs by 12–18%; general LLMs achieve <10% accuracy |
| **HCAPO** | LLM as post-hoc critic for step-level contributions | +7.7% on WebShop, +13.8% on ALFWorld |
| **MACD** | Counterfactual — replace action with default, measure marginal contribution | Game-theoretic, computationally expensive |

### Multi-Agent Coordination Metrics

| Metric | What It Measures |
|---|---|
| **Planning score** | Successful subtask assignment |
| **Communication score** | Inter-agent message quality |
| **Collaboration success rate** | Collective outcome quality |

**Critical insight (Google Cloud):** "If Agent A passes wrong information, the system fails even if Agent B's logic is perfect. Conversely, Agent A's task completion score might be zero because it didn't issue the refund, but it performed its role perfectly by handing off correctly." Evaluate agents by their role contribution, not just their individual output.

### Framework Observability for Multi-Agent

| Framework | Strengths | Limitations |
|---|---|---|
| **LangGraph/LangSmith** | Token counts per node, trajectory match evaluators, time-travel replay | Commercial dependency |
| **CrewAI** | Role-based evaluation mapping | Limited logging capabilities |
| **AutoGen** | Conversation-based debugging | Less granular tracing for non-chat workflows |

---

## LLM-as-Judge

53% of organizations use LLM-as-judge in production. Agreement with human preferences: ~80% (matches inter-human agreement). But significant failure modes exist.

### Paradigms

| Paradigm | How It Works | Best For | Trade-off |
|---|---|---|---|
| **Pointwise** | Score single output against rubric (1–5) | Production monitoring at scale | Less stable than pairwise |
| **Pairwise** | Judge which of two outputs is better | Stable judgments | O(n²) complexity — impractical at scale |
| **Reference-guided** | Compare output against ground truth | When ground truth exists | Requires maintaining reference answers |
| **Reference-free** | Evaluate quality from criteria alone | When no ground truth exists | Less precise |

**Agent-as-a-Judge** (Zhuge et al., 2024): Use an agent to evaluate another agent — examines the entire chain of actions, not just the final answer.

For known biases and mitigations, calibration requirements, judge model selection, and cost optimization strategies, see `llm-as-judge.md`.

---

## Human Evaluation

**When to use:** High-stakes/safety-critical decisions, novel tasks lacking clear criteria, domain expertise requirements (medical, legal, financial), building ground-truth datasets for calibrating automated judges.

**When NOT to use:** High-volume production monitoring, regression testing, CI/CD pipelines, well-defined criteria with established rubrics.

**Cost:** 500×–5,000× more expensive than LLM-as-judge.

### Hybrid Approach (Recommended)

Automate routine scoring with LLM judges. Reserve human review for:
- High-ambiguity cases (where judge confidence is low)
- Safety-critical decisions
- Calibration and validation
- Edge cases flagged by monitoring

Research shows hybrid approaches improve quality by **40%** vs purely automated, while reducing manual workload by ~80%.

### Agent Trace Annotation Dimensions

When human evaluators review agent traces, assess: final output quality, intermediate reasoning steps, tool call correctness, trajectory efficiency, error identification in multi-step chains, constraint adherence.

---

## Safety Evaluation

Only **4 of 30 major AI agents** publish agent-specific system cards. 83% disclose no safety results. 77% have no third-party testing.

### OWASP Top 10 for Agentic Applications (December 2025)

1. Agent goal hijack
2. Tool misuse and exploitation
3. Identity and privilege abuse
4. Agentic supply chain vulnerabilities
5. Unexpected code execution
6. Knowledge/memory poisoning
7. Insecure inter-agent communication
8. Output disclosure
9. Overreliance on agents
10. Rogue agents

### Safety Benchmarks

| Benchmark | What It Tests | Key Finding |
|---|---|---|
| **AgentHarm** | 110 malicious agent tasks, 11 harm categories | GPT-4o completed 48.4% of harmful requests without any jailbreak |
| **InjecAgent** | 1,054 indirect prompt injection tests | ReAct-prompted GPT-4 vulnerable 24%, rising to 47% under enhanced attacks |
| **AgentDojo** | 97 tasks + 629 security tests | Measures utility and security simultaneously |

### Red-Teaming Tools

| Tool | Scope | Best For |
|---|---|---|
| **Microsoft PyRIT** | Multi-turn/multimodal attacks, extensible scoring | Enterprise standard — generates thousands of prompts in hours |
| **Garak** (NVIDIA) | 120+ vulnerability categories | Broad vulnerability scanning |
| **promptfoo** | 50+ vulnerability types, CI/CD integrated | Red-teaming within existing eval pipeline |
| **DeepTeam** | 16 agentic vulnerabilities, 6 agent-specific attacks | Agent-specific attack patterns |

**When to use:** Before any production deployment. Integrate red-teaming into CI/CD alongside functional evals.

### Regulatory Context

| Regulation | Status (March 2026) | Impact |
|---|---|---|
| **EU AI Act** | AI literacy + bans in effect Feb 2025; GPAI Aug 2025; full Aug 2026 | Mandatory compliance for EU-deployed agents |
| **NIST AI RMF** | Voluntary; Cybersecurity AI Profile Dec 2025 | Four-function structure (Govern, Map, Measure, Manage) |
| **MITRE ATLAS** | 14 new agent-specific techniques Oct 2025 | Threat modeling framework for agents |

---

## Production Monitoring

### Platform Comparison

| Platform | Model | Best For | Starting Price |
|---|---|---|---|
| **LangSmith** | Commercial | LangChain/LangGraph teams | Free (5K traces) → $39/user/mo |
| **Braintrust** | Commercial | CI/CD eval automation, A/B testing | Free tier → usage-based |
| **Langfuse** | Open-source (MIT) | Self-hosting, data sovereignty | Free (50K obs) → Pro $59/mo |
| **Arize Phoenix** | OSS + Commercial | Production monitoring, drift detection | Phoenix free; AX paid |
| **W&B Weave** | Commercial (OSS SDK) | ML + LLM unified tracking | Free → Pro $50/user/mo |
| **Helicone** | OSS (Apache 2.0) | Quick setup, cost optimization | Free (10K logs) → paid |
| **Portkey** | Commercial | Governance, guardrails, compliance | Free → $49/mo |

**OpenTelemetry** is the vendor-neutral standard. GenAI semantic conventions (v1.37+) provide standard schemas for prompts, responses, token usage, and tool calls. **OpenLLMetry** (Traceloop) extends OTel with LLM-specific auto-instrumentation.

### What to Monitor

| Dimension | Metrics | Alert Threshold |
|---|---|---|
| **Latency** | p50, p95, p99 with per-span breakdowns | Varies by modality |
| **Cost** | Per request, per user/session, daily/weekly spend | >20–30% increase per task |
| **Error rates** | By type: API errors, timeouts, tool failures, guardrail violations | Any sustained increase |
| **Quality** | LLM-as-judge on sampled production traffic | >5–10% drop in success rate |
| **Drift** | Input query distributions, embedding shifts, score distribution changes | Statistical significance test |

### Regression Detection and Deployment Gates

Block merges/deploys on:
- **>5–10% drops** in success rate
- **>20–30% increases** in cost per task

### A/B Testing Patterns

1. **Offline A/B**: Run variants against the same golden dataset
2. **Production A/B**: Traffic splitting with per-variant metric monitoring
3. **Simulation-based A/B**: LLM agents simulate user conversations before production exposure

DoorDash's simulation-evaluation flywheel reduced hallucinations by **90%** in simulation, which carried over to production.

---

## Building an Eval Pipeline

### Recommended Toolchain

| Tool | Purpose | When to Use |
|---|---|---|
| **promptfoo** | Declarative YAML eval configs, CI/CD integration, red-teaming | Starting point for most teams; 50+ vulnerability types |
| **Inspect AI** (UK AISI) | Safety evaluations, agentic benchmarks | 100+ pre-built evals (SWE-bench, GAIA, Cybench); MIT license |
| **DeepEval** | pytest-style LLM testing, 30+ metrics | Agent-specific: TaskCompletion, ToolCorrectness, PlanQuality |
| **Langfuse** / **Braintrust** | Production monitoring, tracing, data flywheel | Langfuse for self-hosting; Braintrust for CI/CD automation |

### Example: promptfoo Agent Eval Config

```yaml
providers:
  - id: anthropic:claude-agent-sdk
    config:
      model: claude-sonnet-4-6-20250514
      working_dir: ./project
tests:
  - assert:
      - type: llm-rubric
        value: "Did the agent correctly create the requested module?"
      - type: cost
        threshold: 0.25
      - type: latency
        threshold: 30000
```

### Example: CI/CD Integration

```yaml
name: Agent Evaluation
on: pull_request
jobs:
  evaluate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/cache@v4
        with:
          path: ~/.promptfoo/cache
          key: ${{ runner.os }}-promptfoo-${{ hashFiles('prompts/**') }}
      - uses: promptfoo/promptfoo-action@v1
        with:
          pass-threshold: 80
```

### Recommended Eval Directory Structure

```
evals/
├── datasets/           # Version-controlled golden datasets
│   ├── golden_v1.json
│   └── production_sample_2026_03.json
├── scorers/            # Custom scoring functions
│   ├── factuality.py
│   ├── tool_correctness.py
│   └── custom_rubric.py
├── configs/            # Eval framework configs
│   └── promptfooconfig.yaml
├── tests/              # pytest-compatible eval tests
│   ├── test_rag_quality.py
│   ├── test_agent_trajectory.py
│   └── test_safety.py
└── reports/            # Auto-generated results
```

### Handling Non-Determinism

- Run each test case **3–5 times** with configurable aggregation
- Set `temperature=0` for maximum reproducibility
- Use semantic matching (LLM rubrics, embedding similarity) rather than exact string comparison
- Set **threshold-based assertions** (e.g., 85% pass rate minimum) rather than expecting 100%
- Compare score distributions across variants with statistical significance testing

### The Data Flywheel

1. **Instrument** all production traces with metadata
2. **Score** production traffic via online LLM-as-judge evaluations
3. **Identify failures** by filtering low-scoring traces, clustering by failure type
4. **Curate** — promote failing traces to eval datasets (one-click in Braintrust/LangSmith)
5. **Improve** prompts and architecture based on patterns
6. **Re-evaluate** against the growing dataset
7. **Deploy** via A/B testing with post-deployment monitoring
8. Repeat

---

## Best Practices and Anti-Patterns

### Consensus Best Practices

1. **Start with 20–50 eval tasks derived from real failures.** Convert bug reports, support tickets, user-reported failures into test cases. Don't wait for perfection.
2. **Practice evaluation-driven development (EDD).** Define success criteria before building features. Build evals for planned capabilities before agents can fulfill them.
3. **Combine three grader types.** Code-based (fast, cheap, objective) + model-based (flexible, scalable) + human (gold standard, calibration). Calibrate monthly.
4. **Evaluate process AND outcome.** Track trajectory quality, tool call sequences, intermediate reasoning alongside final outputs.
5. **Use held-out test sets.** Prevent overfitting. Anthropic reports additional performance improvements beyond "training" evals when testing on held-out sets.
6. **Separate capability evals from regression evals.** Capability evals push boundaries; high-passing ones graduate into regression suite.
7. **Run multiple trials per task.** Agent behavior is stochastic. pass@k for capability, pass^k for reliability.
8. **Integrate evals into CI/CD.** Every code, prompt, or model change triggers automated evaluation with quality gates.
9. **Create continuous feedback loops.** Production failures → new test cases → expanded eval suite → improved agent → deploy → monitor → repeat.
10. **Layer evaluations for efficiency.** Run fast/cheap deterministic checks first (exact match, regex, schema), expensive LLM-judge checks second.

### The Ten Anti-Patterns

| # | Anti-Pattern | Problem | Fix |
|---|---|---|---|
| 1 | **Vibes-based evaluation** | Spreadsheet spot-checking produces false confidence | Measurable success criteria, structured metrics, automated scoring |
| 2 | **Output-only evaluation** | Correct output via incorrect reasoning = time bomb | Evaluate trajectory and intermediate steps |
| 3 | **Happy-path-only testing** | Misses adversarial, ambiguous, off-topic, and failure scenarios | Include adversarial examples, multi-step failure scenarios |
| 4 | **Treating agent eval like software testing** | Agents are non-deterministic with compounding errors | Run multiple trials, use statistical aggregation |
| 5 | **Single-metric reliance** | Benchmark success ≠ production success | Multidimensional: correctness, process, cost, latency, safety |
| 6 | **Ignoring cost and latency** | Unconstrained agents: $5–8/task; Reflexion loops: 50× tokens | Model costs before building; set budgets |
| 7 | **Eval set contamination** | Search-time contamination: agents find answers online during eval | Block known sources; use fresh benchmarks |
| 8 | **Benchmark overfitting** | Optimizing same test cases ≠ real-world improvement | Regularly refresh eval sets; maintain held-out sets |
| 9 | **Not versioning evals** | "We ran evals at launch" provides no ongoing assurance | Version eval datasets, judge prompts, and rubrics alongside code |
| 10 | **Trusting automation blindly** | "We bought the evaluator" ≠ evaluation engineering | Tools are commodities; the process is the differentiator |

### Evaluation Maturity Ladder

| Stage | Description | Key Capability |
|---|---|---|
| **1. No evals** | Manual testing, intuition | — |
| **2. Vibes-based** | Spreadsheet spot-checking | Human judgment on samples |
| **3. Basic automated** | 20–50 tasks, some deterministic graders | Reproducible checks |
| **4. Systematic** | Comprehensive suites, CI/CD integration, production monitoring | Continuous quality assurance |
| **5. Eval-driven development** | Evals define capabilities before implementation, feedback loops | Evaluation as engineering discipline |

---

## Core Eval Dimensions for Agents

The five most common LLM-as-Judge evaluation dimensions for production agents. Use these as the starting point for your eval suite — add domain-specific dimensions as needed.

For rubric design theory, scale selection, and bias mitigation, see `llm-as-judge.md` and `binary-evals.md`.

### The Five Dimensions

| Dimension | What It Measures | When It Matters Most |
|---|---|---|
| **Hallucination** | Whether the response contains fabricated facts, invented sources, or claims unsupported by the provided context | RAG agents, knowledge-base QA, any agent that retrieves and synthesizes information |
| **Toxicity** | Whether the response contains harmful, offensive, discriminatory, or inappropriate content | All user-facing agents — non-negotiable safety baseline |
| **Helpfulness** | Whether the response addresses the user's actual need with accurate, actionable, complete information | Task-oriented agents, customer support, advisory systems |
| **Relevancy** | Whether the response stays on topic and avoids tangential content | Agents handling diverse queries, routed multi-agent systems |
| **Conciseness** | Whether the response is free of unnecessary verbosity, filler, and repetition | Chat agents, voice agents, any latency-sensitive application |

### Rubric Design Pattern

Each dimension should follow this structure when building judge prompts:

1. **Role statement** — "You are an impartial evaluation judge"
2. **Task definition** — What specific quality to evaluate
3. **Scoring scale** — Use 0.0–1.0 continuous (0.0 = worst, 1.0 = best) or binary pass/fail. See `binary-evals.md` for when binary is better.
4. **Anchor descriptions** — Define what 0.0, 0.5, and 1.0 look like concretely
5. **Input specification** — What the judge receives (user input, context, agent output)
6. **Reasoning instruction** — "Think step by step" with explicit evaluation steps
7. **Output format** — Structured JSON: `{"score": <float>, "reasoning": "<explanation>"}`

### Selecting Dimensions

Not every agent needs all five. Select based on risk profile:

| Agent Type | Must Have | Should Have | Nice to Have |
|---|---|---|---|
| **Customer-facing chat** | Toxicity, Helpfulness | Hallucination, Relevancy | Conciseness |
| **RAG / knowledge QA** | Hallucination, Relevancy | Helpfulness | Conciseness, Toxicity |
| **Code generation** | Helpfulness (correctness) | — | Conciseness |
| **Voice / realtime** | Conciseness, Helpfulness | Toxicity | Relevancy |
| **Internal tooling** | Helpfulness | Hallucination | — |

### Running Evaluations at Scale

| Concern | Recommendation |
|---|---|
| **Judge model** | Use a model at least as capable as the agent being judged. Cross-model evaluation reduces self-preference bias. |
| **Scoring** | Require structured output (JSON with score + reasoning). Parse programmatically. |
| **Sampling** | Score 5–10% of production traffic, not everything. Calibrate sampling rate against your quality SLA. |
| **Rate limits** | Add delays between judge calls (5–10s). Batch evaluations are not latency-sensitive. |
| **Trace integration** | Push scores back to your tracing platform (LangSmith, Langfuse) for filtering and trending. |
| **Calibration** | Validate judge agreement against 100–500 human-labeled examples. Recalibrate monthly. See LLM-as-Judge section above. |
| **Alerting** | Set regression gates: alert if any dimension's average score degrades by >5–10% week-over-week. |
