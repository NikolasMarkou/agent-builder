# Prompt Structuring Guide

How to structure prompts for AI agents: delimiter formats, architecture, techniques, output control, and model-specific guidance.

## Table of Contents

1. [Delimiter Formats](#1-delimiter-formats)
2. [Prompt Architecture](#2-prompt-architecture)
3. [Core Prompting Techniques](#3-core-prompting-techniques)
4. [Layered Prompting](#4-layered-prompting-combining-techniques)
5. [Controlling Output](#5-controlling-output)
6. [Position Bias and Ordering](#6-position-bias-and-ordering)
7. [Model-Specific Notes](#7-model-specific-notes)
8. [Anti-Patterns](#8-anti-patterns)
9. [Quick Reference](#9-quick-reference-universal-prompt-skeleton)

---

## 1. Delimiter Formats

Three dominant formats for structuring prompts. Each has trade-offs depending on the model and task complexity.

### XML Tags

XML is the only structured format explicitly recommended by all three major providers (Anthropic, Google, OpenAI). Claude was specifically trained on XML-tagged prompts, making it the strongest format for that model family. OpenAI's GPT-4.1+ prompt guide also confirms improved adherence to XML-structured information.

**Why XML works well:**

- Explicit open/close delimiters eliminate ambiguity about where sections begin and end.
- Tokenization allows the model to check whether a tag has been closed, confirming when a context block is complete.
- Supports arbitrary nesting and custom semantic labels.
- Stronger resistance to prompt injection compared to markdown (the explicit boundary makes it harder for injected text to "escape" a content block).

**Core pattern:**

```xml
<role>You are a senior data analyst.</role>

<context>
The dataset contains 12 months of sales data across 4 regions.
</context>

<instructions>
1. Identify the top-performing region.
2. Explain the trend in Q4.
3. Flag any anomalies.
</instructions>

<output_format>
Respond in a JSON object with keys: top_region, q4_trend, anomalies.
</output_format>
```

**Nesting for complex data:**

```xml
<documents>
  <document index="1">
    <source>Q3 Report</source>
    <document_content>...</document_content>
  </document>
  <document index="2">
    <source>Q4 Report</source>
    <document_content>...</document_content>
  </document>
</documents>
```

**Key rules:**

- Tag names should be descriptive and consistent across prompts.
- Reference tags by name in instructions: "Using the data in `<context>` tags..."
- No canonical "best" tag names exist. Use whatever makes semantic sense.
- Nest tags when content has natural hierarchy.

**When to use:** Mixed content types (instructions + data + examples + constraints), complex/nested structures, prompt injection resistance matters.

**When NOT to use:** Simple single-task instructions where markdown suffices, token-constrained environments where XML overhead is costly.

### Markdown

Markdown is the native format for OpenAI models. GPT system prompts have historically been markdown-based. Highly readable and familiar to most developers.

**OpenAI's recommended prompt skeleton (GPT-4.1+ prompt guide):**

```markdown
# Role and Objective
# Instructions
## Sub-categories for detailed instructions
# Reasoning Steps
# Output Format
# Examples
## Example 1
# Context
# Final instructions and prompt to think step by step
```

**When to use:** Straightforward instruction sets, OpenAI-primary deployments, human-readable prompts.

**When NOT to use:** Complex nested structures, mixed content types requiring clear boundaries, high prompt injection risk.

### YAML

Less common but understood by all major models. Useful for configuration-like prompts or structured key-value data.

```yaml
role: senior financial analyst
task: analyze quarterly earnings
constraints:
  - max 500 words
  - include year-over-year comparison
  - cite specific figures
output_format: markdown table
```

**When to use:** Configuration-like prompts, structured key-value data, minimal syntax desired.

**When NOT to use:** Complex nesting (indentation-sensitive tokenization can break it), prompts with mixed content types.

### Format Selection Matrix

| Factor | XML | Markdown | YAML |
|---|---|---|---|
| Claude (Anthropic) | Best | Good | Good |
| GPT (OpenAI) | Good | Best | Good |
| Gemini (Google) | Good | Good | Good |
| Complex/nested structure | Best | Weak | Good |
| Human readability | Moderate | Best | Good |
| Token efficiency | Worst | Best | Moderate |
| Prompt injection resistance | Best | Weakest | Moderate |
| Parseability of output | Best | Moderate | Good |

**Practical rule:** If your prompt contains mixed content types (instructions + data + examples + constraints), use XML. If it is a straightforward instruction set, markdown is fine. If accuracy matters more than token cost, prefer XML.

---

## 2. Prompt Architecture

Regardless of format, high-performing prompts share a consistent internal structure. Order matters.

### The 7-Block Prompt Template

```
1. ROLE        — Who the model is
2. CONTEXT     — Background information, data, documents
3. TASK        — What to do (the core instruction)
4. CONSTRAINTS — Boundaries, exclusions, limits
5. EXAMPLES    — Few-shot demonstrations
6. OUTPUT FORMAT — Structure, schema, length
7. REASONING   — How to think (CoT trigger or step outline)
```

Not every prompt needs all 7 blocks. Simple tasks might only need TASK + OUTPUT FORMAT. Scale structure to complexity.

**Example (XML, full structure):**

```xml
<role>You are a legal contract reviewer with 15 years of experience.</role>

<context>
The following contract is between Company A (seller) and Company B (buyer)
for a SaaS licensing agreement. Jurisdiction: Delaware.
</context>

<task>
Review the contract for risks to Company B. Identify problematic clauses
and suggest specific alternative language.
</task>

<constraints>
- Focus only on liability, termination, and IP ownership clauses.
- Do not summarize the entire contract.
- Flag anything that deviates from standard SaaS agreements.
</constraints>

<examples>
<example>
<clause>Seller shall not be liable for any indirect damages.</clause>
<risk>Overly broad liability exclusion. Buyer has no recourse for consequential losses like lost revenue.</risk>
<suggestion>Replace with: "Seller's liability for indirect damages shall be capped at 12 months of fees paid."</suggestion>
</example>
</examples>

<output_format>
For each issue found, provide:
- Clause reference (section number)
- Risk assessment (high/medium/low)
- Suggested alternative language
Format as a markdown table.
</output_format>

<reasoning>
Analyze each clause individually. Consider standard market terms for
enterprise SaaS agreements. Compare against buyer-favorable precedents.
</reasoning>
```

---

## 3. Core Prompting Techniques

### Zero-Shot Prompting

No examples provided. The model relies entirely on its training. Works well for simple, well-defined tasks.

```
Classify the sentiment of this review as positive, negative, or neutral:
"The battery life is impressive but the camera quality is disappointing."
```

**When to use:** Simple classification, summarization, translation, or any task where the model already understands the format.

**When NOT to use:** Tasks requiring specific output format, domain-specific reasoning, or nuanced judgment where examples would clarify expectations.

### Few-Shot Prompting

Provide 2-5 examples to establish the pattern. The model mimics the demonstrated format and reasoning style.

```xml
<examples>
<example>
<input>The restaurant was noisy but the pasta was incredible.</input>
<output>mixed</output>
</example>
<example>
<input>Absolutely terrible service. Never coming back.</input>
<output>negative</output>
</example>
<example>
<input>Best purchase I've made all year.</input>
<output>positive</output>
</example>
</examples>

<input>The hotel room was clean but the WiFi kept dropping.</input>
```

**Best practices:**

- Use 3-5 diverse examples covering edge cases.
- Vary the order of categories to prevent overfitting.
- Include at least one "tricky" example that demonstrates nuanced judgment.
- For recent strong models, few-shot exemplars primarily enforce output format rather than teach reasoning. The model already knows how to reason; examples show it *what shape* you want the answer in.

**When to use:** Enforcing specific output format, demonstrating domain-specific patterns, handling edge cases.

**When NOT to use:** More than 10 examples (diminishing returns, overfitting risk), tasks where the model already produces the right format zero-shot.

### Chain-of-Thought (CoT)

Force the model to show intermediate reasoning steps before producing a final answer. Critical for math, logic, multi-step analysis.

**Zero-shot CoT** (simplest form):

```
How many r's are in the word "strawberry"? Think step by step.
```

**Few-shot CoT** (with demonstrated reasoning):

```xml
<example>
<question>A store has 15 apples. 8 are sold in the morning, then 6 more are delivered. How many apples are there?</question>
<reasoning>Start with 15. Subtract 8 sold = 7. Add 6 delivered = 13.</reasoning>
<answer>13</answer>
</example>
```

**Structured CoT with XML:**

```xml
<instructions>
Solve the following problem. Show your work inside <thinking> tags,
then provide your final answer inside <answer> tags.
</instructions>
```

This gives you parseable output: extract the `<answer>` block programmatically and discard the reasoning.

**Key finding (2025 research):** For top-tier models (GPT-4+, Claude Opus/Sonnet, Gemini Pro), zero-shot CoT ("think step by step") often matches or exceeds few-shot CoT performance. The few-shot examples in CoT primarily enforce output structure, not reasoning ability.

**When to use:** Math, logic, multi-step analysis, tasks where accuracy depends on intermediate reasoning.

**When NOT to use:** Simple factual recall, classification tasks where reasoning adds latency without improving accuracy, latency-sensitive applications.

### Self-Consistency Prompting

Generate multiple reasoning paths and select the most common answer. Implemented by running the same prompt N times (typically 5-10) with temperature > 0, then taking the majority vote.

Useful for arithmetic, commonsense reasoning, and any task where a single reasoning chain might go wrong.

**When to use:** High-stakes decisions where accuracy matters more than cost, math and logic problems.

**When NOT to use:** Cost-sensitive applications (multiplies API calls), creative tasks where diversity is the goal, latency-constrained environments.

### Meta Prompting

Provide the abstract structure of how to solve a problem, not specific examples.

```
To solve this problem:
Step 1: Identify the variables.
Step 2: Determine which formula applies.
Step 3: Substitute and solve.
Step 4: Verify the result.
```

More token-efficient than few-shot. Reduces bias from specific examples. Works well for code generation and math.

**When to use:** Procedural tasks, code generation, mathematical problem-solving, when you want to avoid example bias.

**When NOT to use:** Tasks where concrete examples are more informative than abstract procedures, creative writing.

### Prompt Chaining

Break complex tasks into a pipeline of sequential prompts. The output of prompt N becomes input to prompt N+1.

```
Prompt 1: Extract all dates and entities from this document.
Prompt 2: Using the extracted entities, identify relationships between them.
Prompt 3: Using the relationships, generate a timeline narrative.
```

**When to use:** Any task too complex for a single prompt. Reduces hallucination because each step is focused and verifiable. Maps directly to agent sequential topology patterns.

**When NOT to use:** Simple tasks achievable in a single prompt, latency-sensitive scenarios where pipeline overhead is costly.

---

## 4. Layered Prompting (Combining Techniques)

The highest-quality outputs come from stacking multiple techniques in a single prompt.

**Pattern: Role + Constraints + CoT + Output Format**

```xml
<role>You are a cybersecurity analyst specializing in threat modeling.</role>

<instructions>
Analyze the following system architecture for security vulnerabilities.
Think through each component systematically before writing your conclusion.
</instructions>

<constraints>
- Focus on OWASP Top 10 categories.
- Assume the attacker has network access but no credentials.
- Rate each vulnerability as critical, high, medium, or low.
</constraints>

<output_format>
Provide your analysis as a 3-bullet executive summary, followed by a
detailed table with columns: Component, Vulnerability, OWASP Category, Severity, Remediation.
</output_format>
```

---

## 5. Controlling Output

### Prefilling (Claude-specific)

Start the assistant's response to steer the output format:

```
Human: Extract the names from this text as JSON.
Assistant: {"names": [
```

The model will continue from where you left off, locked into JSON format. Combine with a stop sequence (e.g., `]}`) for clean extraction.

### Structured Output Enforcement

For classification-specific structured output (intent detection, routing decisions), see `structured-classification.md` — covers schema design with reasoning-before-decision ordering, enum enforcement, and constrained decoding engines.

Request specific formats explicitly:

```xml
<output_format>
Respond ONLY with a valid JSON object. No preamble, no explanation, no markdown fences.
Schema:
{
  "summary": string,
  "confidence": number (0-1),
  "sources": string[]
}
</output_format>
```

### Negative Constraints (Use Sparingly)

Telling the model what NOT to do can backfire (reverse psychology effect). Prefer positive framing:

| Instead of | Use |
|---|---|
| "Don't be verbose" | "Be concise. Max 3 sentences." |
| "Don't use jargon" | "Use plain language a 10-year-old would understand." |
| "Don't make things up" | "Only include information from the provided documents. If unsure, say 'I don't know.'" |

---

## 6. Position Bias and Ordering

Models do not treat all parts of a prompt equally.

- **Claude and GPT:** Tend to weight information at the beginning more heavily.
- **Some open-source models:** Perform better with the most relevant examples last.
- **Long context:** Place the most critical instructions both at the beginning AND the end of the prompt ("sandwich" technique). Models tend to lose focus in the middle of long contexts.

For few-shot examples, put the most representative example first. For document-grounded tasks, place the instruction to quote/reference the documents before the documents themselves.

---

## 7. Model-Specific Notes

### Claude (Anthropic)
- Trained on XML. Use XML tags for any prompt with mixed content types.
- Follows instructions in human/user messages better than system messages. Use system messages for role-setting and high-level behavior. Put detailed instructions in user messages.
- Extended thinking: For complex reasoning, Claude can use `<thinking>` blocks natively. You don't need to prompt for CoT; just ask the question and let extended thinking handle it.
- Prefilling works. Use it.

### GPT-4.1+ (OpenAI)
- Start with markdown structure. Fall back to XML for complex prompts.
- Follows instructions more literally than predecessors. Be explicit; don't rely on the model inferring intent.
- Reasoning models (o1, o3): Use `developer` messages instead of `system` messages. Add "Formatting re-enabled" as the first line if you want markdown output.
- Parallel tool calls can occasionally be incorrect. Test and disable if needed.

### Gemini (Google)
- Flexible with both XML and markdown.
- Excels at managing intra-session context over long inputs.
- No persistent memory in consumer tools as of early 2026.

---

## 8. Anti-Patterns

| Anti-Pattern | Why It Fails |
|---|---|
| Vague instructions ("make it better") | Model has to guess what "better" means |
| Wall of text with no structure | Ambiguity increases, instruction-following drops |
| Too many few-shot examples (10+) | Diminishing returns; can cause overfitting to example patterns |
| Mixing instructions and data without delimiters | Model confuses what to do with what to process |
| Heavy negative prompting | Can trigger the exact behavior you're trying to avoid |
| Same prompt across different models | Each model has format preferences; port prompts deliberately |
| Ignoring output format specification | Model defaults to whatever it wants |

---

## 9. Quick Reference: Universal Prompt Skeleton

```xml
<system>
[Role definition. 1-2 sentences max.]
</system>

<context>
[Background info, documents, data. Clearly delimited.]
</context>

<task>
[Single clear instruction. What do you want?]
</task>

<constraints>
[Boundaries: length, scope, exclusions, tone.]
</constraints>

<examples>
<example>
  <input>[Sample input]</input>
  <output>[Expected output]</output>
</example>
</examples>

<output_format>
[Exact format: JSON, markdown table, bullet list, prose, etc.]
</output_format>

<reasoning>
[Optional. "Think step by step" or explicit step outline.]
</reasoning>
```

This skeleton works across Claude, GPT, and Gemini. Adjust tag names and format (XML vs markdown headers) to match the target model's preferences.
