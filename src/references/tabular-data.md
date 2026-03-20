# Structuring Tabular Data for LLM Consumption

How to serialize tables, spreadsheets, and structured records for LLM prompts: format selection, size-based strategies, and cost/accuracy tradeoffs.

## Table of Contents

1. [The Core Problem](#1-the-core-problem)
2. [Serialization Formats Ranked](#2-serialization-formats-ranked)
3. [Format Deep Dive](#3-format-deep-dive)
4. [Size-Based Strategy](#4-size-based-strategy)
5. [Critical Best Practices](#5-critical-best-practices)
6. [Format Selection Decision Tree](#6-format-selection-decision-tree)
7. [Model-Specific Notes](#7-model-specific-notes)
8. [Token Cost Comparison](#8-token-cost-comparison-1000-flat-records-8-fields-each)

---

## 1. The Core Problem

LLMs process text sequentially, token by token. Tables are inherently two-dimensional (rows x columns). This mismatch means the serialization format you choose directly impacts accuracy, cost, and context window utilization. Research consistently shows that format choice alone can swing accuracy by 15-20 percentage points on the same data with the same model.

---

## 2. Serialization Formats Ranked

Benchmark data from ImprovingAgents (Sep 2025, GPT-4o-mini, 1000 records, 1000 questions):

| Format | Accuracy | Tokens (1K records) | Notes |
|---|---|---|---|
| **Markdown-KV** | 60.7% | 52,104 | Key-value pairs under markdown headers per record |
| **XML** | 56.0% | 76,114 | High accuracy, high token cost |
| **INI** | 55.7% | 48,100 | Surprisingly strong, low token cost |
| **YAML** | 54.7% | 55,395 | Clean, good balance |
| **HTML table** | 53.6% | 75,204 | GPT models trained on web data; good comprehension |
| **JSON** | 52.3% | 66,396 | Familiar but verbose |
| **Markdown table** | 51.9% | 25,140 | Most token-efficient structured format |
| **Natural language** | 49.6% | 43,411 | Baseline prose description |
| **JSONL** | 45.0% | 54,407 | Poor; loses header context between lines |
| **CSV** | 44.3% | 19,524 | Most compact, worst accuracy |
| **Pipe-delimited** | 41.1% | 43,098 | Worst overall |

Additional findings from academic research (Sui et al., 2023): HTML and XML outperform delimiter-separated formats for GPT-3.5 and GPT-4 on table QA and fact verification tasks. The hypothesis is that GPT models were exposed to massive amounts of web-formatted tables during training.

TOON benchmarks (Oct 2025, 4 models, 209 questions, mixed structures):

| Format | Accuracy | Efficiency (acc%/1K tokens) |
|---|---|---|
| **TOON** | 76.4% | 27.7 |
| **JSON compact** | 73.7% | 23.7 |
| **YAML** | 74.5% | 19.9 |
| **JSON formatted** | 75.0% | 16.4 |
| **XML** | 72.1% | 13.8 |

---

## 3. Format Deep Dive

### Markdown-KV (highest accuracy in flat data benchmarks)

Each record gets its own markdown heading with key-value pairs. The model sees clear record boundaries and field labels repeated per record.

```markdown
## Record 1
id: 1
name: Alice Chen
department: Engineering
salary: 95000
years_experience: 7

## Record 2
id: 2
name: Bob Martinez
department: Sales
salary: 82000
years_experience: 4
```

**When to use:** Lookup-heavy tasks, small datasets (<50 records), when accuracy matters more than token cost.

**When NOT to use:** Large datasets (token overhead is 2.7x CSV), streaming/incremental data, when token budget is constrained.

### HTML Table

```html
<table>
<thead>
<tr><th>id</th><th>name</th><th>department</th><th>salary</th></tr>
</thead>
<tbody>
<tr><td>1</td><td>Alice Chen</td><td>Engineering</td><td>95000</td></tr>
<tr><td>2</td><td>Bob Martinez</td><td>Sales</td><td>82000</td></tr>
</tbody>
</table>
```

**When to use:** GPT-primary deployments (native web training), explicit header/body separation needed.

**When NOT to use:** Token-constrained environments (very high tag overhead per cell), Claude-primary deployments (XML is better).

### XML

```xml
<records>
  <record id="1">
    <name>Alice Chen</name>
    <department>Engineering</department>
    <salary>95000</salary>
  </record>
  <record id="2">
    <name>Bob Martinez</name>
    <department>Sales</department>
    <salary>82000</salary>
  </record>
</records>
```

**When to use:** Claude-primary deployments, nested/hierarchical data, when accuracy is paramount.

**When NOT to use:** Token-constrained environments (most expensive format), large flat datasets where simpler formats suffice.

### Markdown Table

```markdown
| id | name | department | salary |
|----|------|------------|--------|
| 1 | Alice Chen | Engineering | 95000 |
| 2 | Bob Martinez | Sales | 82000 |
```

**When to use:** Medium-sized datasets where token efficiency matters, human-readable output, cross-model compatibility.

**When NOT to use:** Large tables without repeated headers (model loses column tracking), nested data, datasets requiring per-row field labels.

### CSV

```
id,name,department,salary
1,Alice Chen,Engineering,95000
2,Bob Martinez,Sales,82000
```

**When to use:** Absolute minimum token count needed, data is simple and flat, model will write code to process it rather than reasoning over it directly.

**When NOT to use:** Direct LLM reasoning over data (worst accuracy), any dataset where field labels per row matter, data with commas or special characters in values.

### TOON (Token-Oriented Object Notation)

Released October 2025. Designed specifically for LLM input. Declares schema once, streams data as rows.

```
records[2,]
  {id,name,department,salary}
  1,Alice Chen,Engineering,95000
  2,Bob Martinez,Sales,82000
```

**When to use:** Cost optimization on uniform/tabular arrays, large datasets where JSON/XML token cost is prohibitive, declared array lengths help detect truncation.

**When NOT to use:** Deeply nested structures, irregular data shapes, when LLM has not been tested with TOON format (it's new — benchmark first).

---

## 4. Size-Based Strategy

### Small Data (< 50 rows, < 20 columns)

Fits easily in any modern context window. Optimize for accuracy, not tokens.

**Recommended format:** Markdown-KV or XML.

**Approach:**
- Paste the entire dataset inline in the prompt.
- Include all columns, even if not all are relevant (the model can filter).
- Wrap in clear tags: `<data>...</data>` or under a `## Data` heading.
- State the schema explicitly before the data if column meanings are ambiguous.

```xml
<schema>
This table contains employee records.
- id: unique employee identifier
- salary: annual salary in USD before tax
- yoe: years of experience (integer)
</schema>

<data>
## Employee 1
id: 1
name: Alice Chen
salary: 95000
yoe: 7

## Employee 2
id: 2
name: Bob Martinez
salary: 82000
yoe: 4
</data>
```

### Medium Data (50-500 rows)

Starting to strain accuracy. The "lost in the middle" problem becomes real: models attend strongly to the beginning and end of context but lose focus on data in the middle.

**Recommended format:** Markdown table with repeated headers, or TOON.

**Approach:**
- **Repeat headers every 50-100 rows.** This is the single highest-impact technique for medium-sized tables. Formats like CSV, markdown tables, and HTML tables all benefit from re-inserting the header row periodically.
- **Pre-filter columns.** Only include columns relevant to the question. Dropping irrelevant columns reduces noise and token count.
- **Pre-filter rows** if possible. If you know which rows are relevant (via SQL, pandas, or search), send only those.
- **Add row numbers** as an explicit column if the model needs to reference specific rows.
- **Provide a summary row** or metadata block: total row count, column types, value ranges.

```markdown
**Table: Q3 Sales Data (247 rows, showing first 5)**
**Columns: rep_name (string), region (string), revenue (USD), deals_closed (int)**

| row | rep_name | region | revenue | deals_closed |
|-----|----------|--------|---------|--------------|
| 1 | Alice Chen | West | 340000 | 12 |
| 2 | Bob Martinez | East | 285000 | 9 |
| 3 | Carol Wu | West | 410000 | 15 |
| 4 | Dave Patel | South | 195000 | 6 |
| 5 | Eve Johnson | East | 320000 | 11 |

[... 242 more rows ...]

| row | rep_name | region | revenue | deals_closed |
|-----|----------|--------|---------|--------------|
| 246 | Yuki Tanaka | North | 275000 | 8 |
| 247 | Zara Ahmed | South | 305000 | 10 |

**Summary: Total revenue $72.4M, avg deals/rep 9.3, top region West**
```

### Large Data (500+ rows or multi-sheet)

Will not fit in a single prompt, or will severely degrade accuracy even if it technically fits.

**Recommended approach:** Do NOT paste the raw data. Use one of these strategies:

**Strategy 1: Pre-process and summarize**

Run aggregations, pivots, or filters in code (Python/pandas, SQL) before prompting. Send the LLM the *result*, not the raw data.

```xml
<context>
Source: company_sales.xlsx (14,328 rows, 23 columns)
Pre-processed using pandas. Results below.
</context>

<summary_table>
| region | total_revenue | avg_deal_size | top_rep |
|--------|--------------|---------------|---------|
| West | 24.1M | 48200 | Carol Wu |
| East | 19.8M | 41500 | Eve Johnson |
| South | 15.2M | 38000 | Zara Ahmed |
| North | 13.3M | 35800 | Yuki Tanaka |
</summary_table>

<task>
Analyze regional performance differences and recommend resource allocation changes.
</task>
```

**Strategy 2: Chunked retrieval (RAG)**

Split the spreadsheet into chunks, embed them, store in a vector database. At query time, retrieve only the relevant chunks and pass those to the LLM.

For tabular data specifically:
- Chunk by logical groups (by sheet, by category, by date range), not by fixed row count.
- Each chunk should be self-contained: include column headers, schema context, and metadata.
- Keep chunks to 50-100 rows max for optimal retrieval granularity.

**Strategy 3: Map-reduce**

For summarization over large spreadsheets:
1. Split the data into chunks of ~100 rows.
2. Send each chunk to the LLM with the same summarization prompt.
3. Collect all sub-summaries.
4. Send the sub-summaries to the LLM for a final consolidated summary.

**Strategy 4: Code execution**

For analytical questions on large datasets, have the LLM write code (Python/pandas) instead of processing the data directly. The LLM generates the analysis script; the script processes the data.

---

## 5. Critical Best Practices

### Always declare the schema

Never assume the model knows what your columns mean. Explicitly state:
- Column names and their meaning
- Data types (string, integer, USD currency, date in YYYY-MM-DD)
- Units (is "revenue" in thousands? millions? raw dollars?)
- What constitutes a null/missing value

### Repeat headers in long tables

For any format with a single header row (CSV, markdown table, HTML), re-insert the header every 50-100 rows. This is the single easiest improvement for medium-sized tables.

### Pre-filter aggressively

The best data to send an LLM is the minimum data needed to answer the question. Use code to filter rows and columns before constructing the prompt.

### Preserve structural integrity

If extracting tables from PDFs or Excel files, verify the extraction preserved the original structure. Merged cells, multi-level headers, and spanning rows are common sources of corruption.

### Use explicit row identifiers

Add a row number or ID column so the model (and you) can reference specific rows unambiguously.

### State the total count

Tell the model how many rows/records it's looking at. This anchors comprehension, especially if data is truncated.

```
The following table contains 247 records (all included, no truncation).
```

### Handle numbers carefully

- Include units in the column header: `revenue_usd`, `weight_kg`.
- Avoid mixing formatted and raw numbers (don't mix "$45,200" and "45200" in the same column).
- For financial data, be explicit about scale: "all values in thousands of USD."

---

## 6. Format Selection Decision Tree

```
Is the data < 50 rows?
  YES -> Use Markdown-KV or XML. Paste inline.
  NO  -> Is the data 50-500 rows?
    YES -> Can you pre-filter to relevant rows?
      YES -> Filter first, then use Markdown table or TOON.
      NO  -> Use Markdown table with repeated headers every 50-100 rows.
    NO  -> Is the data 500+ rows?
      YES -> Do NOT paste raw data. Choose:
        - Analytical question? -> Have LLM write code.
        - Summarization? -> Map-reduce.
        - Lookup/QA? -> RAG with chunked retrieval.
        - Dashboard/report? -> Pre-aggregate in code, send summary tables.
```

---

## 7. Model-Specific Notes

### Claude (Anthropic)
- XML format for table wrapping works best.
- Wrap data in `<data>` tags, schema in `<schema>` tags.
- For analysis tasks, Claude excels at writing Python/pandas code to process uploaded Excel files directly rather than ingesting raw data into the prompt.

### GPT (OpenAI)
- HTML tables and markdown tables perform well due to web training data.
- GPT-4o follows literal instructions well. Explicitly state "use only the data provided" to prevent hallucination.
- For structured extraction, request JSON output format.

### General
- All major models lose accuracy in the middle of long contexts. Place the most important data and instructions at the beginning and end.
- For any table > 100 rows, strongly consider whether you actually need the LLM to see every row, or whether pre-processing can reduce the data first.
- TOON is promising for cost optimization but is still new. Benchmark on your specific model and data before committing.

---

## 8. Token Cost Comparison (1000 flat records, 8 fields each)

| Format | Tokens | Cost Ratio vs CSV |
|---|---|---|
| CSV | ~19,500 | 1.0x |
| Markdown table | ~25,100 | 1.3x |
| Natural language | ~43,400 | 2.2x |
| INI | ~48,100 | 2.5x |
| Markdown-KV | ~52,100 | 2.7x |
| JSONL | ~54,400 | 2.8x |
| YAML | ~55,400 | 2.8x |
| JSON | ~66,400 | 3.4x |
| HTML table | ~75,200 | 3.9x |
| XML | ~76,100 | 3.9x |

The tradeoff is clear: accuracy and token cost are inversely correlated. The formats that help the model understand the data best (Markdown-KV, XML) are the most expensive. Choose based on whether you're optimizing for correctness or cost.
