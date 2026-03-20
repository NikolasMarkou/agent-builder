# Cheap Text Tools for AI Agents: A Practical Guide

## What this guide covers

Every token an agent feeds into an LLM costs money and burns latency. The single highest-leverage optimization for agentic workflows is **not sending text to the LLM in the first place** when a deterministic tool can do the job. grep, ripgrep, jq, awk, sed, tree-sitter, sqlite -- these tools are free, instant, deterministic, and reproducible. They should handle the heavy lifting of search, filter, and transform. The LLM handles reasoning, judgment, and generation.

This guide covers the three-layer search stack, tool-by-tool reference with agent-specific usage patterns, agent-optimized search tools, cost math, integration patterns, and anti-patterns.

Anthropic's engineering guidance: "Just-in-time context, not pre-inference RAG -- maintain lightweight identifiers, dynamically load data at runtime using tools." Pre-embedding/chunking entire codebases upfront is being replaced by letting agents search with traditional tools.

---

## The three-layer search stack

> **Design axioms: Tiered escalation + Minimize context.** Try exact search first, structural second, semantic only when needed. Each layer up costs more but handles harder queries. The same tiered architecture applies to entity resolution matching (`entity-resolution.md`) and evaluation grading (`evals.md`).

Modern agent text search has converged on three complementary layers. Each serves a different need. An agent should try layers in order: exact first, structural second, semantic only when needed. Each layer up costs more but handles harder queries.

**Layer 1: Exact matching (ripgrep).** Pattern-based text search. Deterministic. Zero cost. Sub-100ms on codebases with 5000+ files. Handles regex, literal strings, file type filtering, .gitignore respect. This is the workhorse.

**Layer 2: Structural search (ast-grep, tree-sitter).** AST-aware code search. Understands syntax -- finds "all async functions without error handling" or "React components using a specific hook." Deterministic. Zero cost. Slightly more setup than ripgrep.

**Layer 3: Semantic search (mgrep, grepai, Probe).** Embedding-based search over code and text. Handles vocabulary mismatch ("authentication" finds `verify_credentials`). Requires indexing. May require API calls for embeddings (local options exist via Ollama). Use when layers 1 and 2 can't express the query.

---

## Tool-by-tool reference

### ripgrep (rg)

A line-oriented search tool that recursively searches directories for regex patterns. Written in Rust. Faster than grep in every real-world benchmark on codebases.

**Why agents should use it instead of grep:**
- Recursive by default (grep requires `-r`)
- Respects .gitignore automatically (skips node_modules, .venv, dist, build)
- Cleaner output with less noise -- fewer files searched means fewer irrelevant results dumped into context
- Smart case handling (case-insensitive if pattern is lowercase)
- Faster: often <100ms even on large repos

**The context window argument.** Every search result goes into the agent's context window. The LLM pays token costs for every line. Cleaner search upstream = fewer tokens = lower cost + lower latency. When .venv or node_modules are ignored, ripgrep might search dozens of source files where grep searched thousands including binary wheels.

**Key flags for agents:**
```bash
rg "pattern"                    # Recursive, respects .gitignore
rg -F "exact.string"           # Fixed string (no regex interpretation)
rg -l "pattern"                # List filenames only (minimal tokens)
rg -c "pattern"                # Count matches per file
rg -t py "pattern"             # Search only Python files
rg -g "*.ts" "pattern"         # Glob-based file filtering
rg --json "pattern"            # Structured JSON output for parsing
rg -C 3 "pattern"              # 3 lines of context around matches
rg -A 5 -B 2 "pattern"         # 5 lines after, 2 before
rg --max-count 10 "pattern"    # Stop after 10 matches per file
```

**Install:** `brew install ripgrep` / `apt install ripgrep` / `choco install ripgrep`

### ast-grep (sg)

A structural code search tool that uses tree-sitter parsers to understand code syntax. Searches by AST pattern, not text.

**When to use over ripgrep.** When the search is about code structure, not text. "Find all functions that call X but don't handle errors." "Find all React useEffect hooks with empty dependency arrays." These are impossible or brittle with regex, trivial with AST patterns.

**Agent integration.** ast-grep has a dedicated MCP server (`ast-grep-mcp`) that lets agents interact with it directly. Agents can develop and refine AST rules through trial and error. There's also a Claude Code skill/plugin that teaches the agent how to write ast-grep patterns.

**Key commands:**
```bash
sg run --pattern 'console.log($ARG)' --lang javascript .
sg run --pattern 'await $EXPR' --lang typescript .
sg scan --rule path/to/rule.yml .
```

**Install:** `npm install -g @ast-grep/cli` / `brew install ast-grep`

### jq

A command-line JSON processor. "Like sed for JSON data." Slice, filter, map, and transform structured data.

**Why agents need it.** API responses, config files, log entries, tool outputs -- all JSON. Agents constantly need to extract specific fields, filter arrays, transform structures. Doing this with an LLM call is absurd when jq handles it in microseconds.

**Key patterns:**
```bash
cat data.json | jq '.results[].name'           # Extract field from array
cat data.json | jq '.items | length'            # Count items
cat data.json | jq '.[] | select(.status == "error")'  # Filter
cat data.json | jq '{name: .title, id: .ref}'   # Reshape
curl -s api.example.com | jq '.data.users[:5]'  # First 5 users
```

**Install:** `brew install jq` / `apt install jq`

### yq

jq but for YAML, XML, TOML, and CSV. Handles the structured data formats that jq can't.

```bash
yq '.services.web.image' docker-compose.yml
yq -i '.version = "2.0"' config.yaml
```

**Install:** `brew install yq` / `pip install yq`

### sed

Stream editor. Find-and-replace on text streams. Ancient, universal, fast.

**Agent use cases.** Bulk text transformations, config file modifications, log processing. The agent writes the sed command; the tool executes it deterministically.

```bash
sed -i 's/old_api_url/new_api_url/g' config.py
sed -n '10,20p' file.txt                        # Print lines 10-20
sed '/^#/d' config.ini                          # Remove comment lines
```

Note: agents (and humans) frequently generate incorrect sed syntax, especially around regex escaping. Using `-F` for fixed strings where possible, or having the LLM generate a small Python script instead, often produces more reliable results.

### awk

Pattern scanning and processing language. Best for columnar data operations.

```bash
ps aux | awk '{sum += $6} END {print sum/1024 " MB"}'  # Sum memory usage
cat data.csv | awk -F',' '{print $1, $3}'               # Extract columns
cat access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head  # Top IPs
```

### sqlite3

Embedded SQL database. Zero-config, serverless, single-file. The most deployed database in the world.

**Why agents should use it.** When data exceeds what grep/awk can handle efficiently -- joins, aggregations, complex filters on structured data. Simon Willison's `sqlite-utils` converts JSON to SQLite instantly. The `llm-tools-sqlite` plugin gives LLM agents direct read-only query access.

```bash
sqlite3 data.db "SELECT department, COUNT(*) FROM employees GROUP BY department"
cat data.json | sqlite-utils insert data.db entries -
sqlite-utils query data.db "SELECT * FROM entries WHERE status='active'"
```

**Install:** Usually pre-installed. `brew install sqlite3` / `apt install sqlite3`

### Additional text tools

| Tool | Purpose | When to use |
|------|---------|-------------|
| `cut` | Extract columns from delimited text | TSV/CSV column extraction |
| `sort` / `uniq` | Sort and deduplicate | Frequency analysis, dedup |
| `wc` | Count lines/words/bytes | Quick size checks |
| `head` / `tail` | First/last N lines | Preview large files cheaply |
| `diff` | Compare files | Change detection |
| `find` | Locate files by name/type/date | File discovery |
| `xargs` | Build commands from stdin | Batch operations |
| `tr` | Character translation | Quick transforms |
| `tee` | Split output to file + stdout | Logging pipeline results |
| `miller` | sed/awk/cut/join for named data | CSV/JSON tabular processing |
| `csvtk` | CSV toolkit | Search, sample, join CSVs |
| `xidel` | HTML/XML/JSON extraction | Scraping, document parsing |

---

## Agent-optimized search tools

A new category of tools has emerged specifically designed for LLM agent workflows, optimizing for token efficiency and search quality.

### Probe

AST-aware structural search combining ripgrep speed with tree-sitter parsing. Key differentiator: returns entire functions/classes/structs, not text lines that break mid-function. Zero indexing required. Deterministic. Fully local.

The agent workflow: user says "find the authentication logic" → LLM generates `probe search "verify_credentials OR authenticate OR login"` → Probe returns complete AST blocks in milliseconds. The LLM translates intent into boolean queries; Probe executes them.

Supports Elasticsearch-style query language: AND, OR, NOT, phrases, `ext:rs`, `lang:python`.

```bash
probe search "authenticate OR login" --lang python
probe search "+required -test" --files-only
```

Has a built-in agent mode and MCP server. Open source.

### grepika

MCP server that replaces built-in Grep with indexed search. Three backends: FTS5 + grep + trigram with weighted score merging. Benchmarked at ~80% fewer bytes vs ripgrep content mode, with ranked results and snippets.

Key tools: `search`, `toc` (directory tree), `outline` (file structure extraction), `refs` (symbol references), `context` (surrounding lines), `diff` (file comparison).

```bash
grepika index --root /path/to/project
grepika search "authentication" --root /path/to/project -l 20 -m combined
```

### grepai

Privacy-first semantic code search using local vector embeddings (Ollama, LM Studio, or OpenAI). Understands code meaning -- "authentication logic" finds `handleUserSession`. Includes call graph tracing.

```bash
grepai init
grepai watch           # Start indexing daemon
grepai search "error handling"
grepai trace callers "Login"
```

MCP server built in for Claude Code, Cursor, Windsurf integration.

### mgrep

Semantic grep by Mixedbread. Requires API authentication. Benchmarked at 2x fewer tokens vs grep-based workflows at similar or better quality in a 50-task evaluation. Supports code, text, PDFs, images. Has agentic multi-hop search mode for complex queries.

```bash
mgrep watch                              # Index project
mgrep "where do we set up auth?"         # Semantic search
mgrep --web --answer "How to integrate X?"  # Web search + summary
```

### AI-grep

Portable, zero-dependency search tool designed for AI/LLM workflows. SQLite FTS5 + ripgrep hybrid. Orient-Locate-Read workflow:

```bash
./ai-grep stats                          # ~500 tokens overview
./ai-grep relevant "your task" --top 5   # Just paths + scores (~100 tokens)
./ai-grep get "src/auth.py" --lines 10-50  # Targeted content retrieval
```

### llm_grep

Pipe any command output through an LLM for intelligent text filtering. Not a replacement for grep -- a complement for when you need semantic understanding of output.

```bash
tail -100 /var/log/syslog | llm_grep "show only error and warning lines"
git diff HEAD~3 | llm_grep "summarize what changed"
```

Supports Ollama local models, AWS Bedrock, any litellm-compatible provider.

---

## Sandboxed execution: just-bash

`just-bash` provides a TypeScript bash interpreter with an in-memory filesystem, designed for AI agents needing secure, sandboxed execution. Supports: grep, awk, sed, jq, yq, sqlite3, find, sort, uniq, wc, head, tail, cut, diff, xargs, and more.

This matters for agents running in browser environments or sandboxed containers where real bash isn't available. The agent gets the full Unix text processing toolkit without filesystem access risks.

---

## Cost math

Consider an agent that needs to find all error handling patterns in a 10,000-file codebase.

**Approach A: Dump files to LLM.**
Embed and retrieve ~50 relevant files. Average 500 lines each = 25,000 lines. At ~4 tokens/line = 100,000 input tokens. At $3/MTok (GPT-4o) = $0.30 per query. The LLM then reasons over all of it.

**Approach B: ripgrep + targeted retrieval.**
`rg -l "catch|except|error" --type py` returns 30 filenames in <100ms. Agent reads 5 most relevant files. 2,500 lines = 10,000 tokens. Cost: $0.03. **10x cheaper.**

**Approach C: ast-grep + surgical extraction.**
`sg run --pattern 'try { $$ } catch($ERR) { $$ }' --lang typescript` returns just the try/catch blocks. Maybe 500 lines total = 2,000 tokens. Cost: $0.006. **50x cheaper than A.**

Over thousands of agent runs per day, this is the difference between a $50/day and a $2,500/day API bill.

Context processing -- not search execution -- dominates cost in agent workflows.

---

## Tool selection decision tree

```
Agent needs to find/process text
  │
  Is the query an exact pattern or regex?
  ├── Yes → ripgrep (rg)
  │
  Is it about code structure (syntax, AST patterns)?
  ├── Yes → ast-grep (sg) or tree-sitter
  │
  Is it structured data (JSON/YAML/CSV/XML)?
  ├── JSON → jq
  ├── YAML/TOML → yq
  ├── CSV → miller, csvtk, or sqlite3
  ├── XML/HTML → xidel, htmlq, pup
  │
  Is it a SQL-expressible query over tabular data?
  ├── Yes → sqlite3
  │
  Is it a natural language / semantic query?
  ├── Yes → Probe, grepai, mgrep, or grepika
  │
  Does the output need semantic understanding/filtering?
  ├── Yes → llm_grep (pipe through small local model)
  │
  None of the above? → Then and only then, send to the LLM
```

---

## Integration patterns

### MCP server pattern

Expose tools as MCP servers so agents discover and call them:

```json
{
  "mcpServers": {
    "grepika": {
      "command": "npx",
      "args": ["-y", "@agentika/grepika", "--mcp"]
    },
    "ast-grep": {
      "command": "npx",
      "args": ["-y", "ast-grep-mcp"]
    }
  }
}
```

### System prompt / CLAUDE.md pattern

Tell the agent which tools to prefer:

```markdown
## Code Search
Prefer these tools over built-in Grep/Glob:
- `rg` for pattern search (always use -F for literal strings)
- `sg` for structural/AST code search
- `jq` for JSON processing
- `sqlite3` for data queries

## Rules
- Never dump entire files into context. Use head/tail/grep to extract relevant sections.
- Use `rg -l` (list files only) before reading full file content.
- For JSON API responses, always pipe through jq to extract relevant fields.
- For CSV data >100 rows, import to sqlite and query.
```

### Bash tool wrapper pattern

Wrap deterministic tools as agent-callable functions:

```python
@tool
def search_codebase(pattern: str, file_type: str = None, max_results: int = 20) -> str:
    """Search codebase for a pattern using ripgrep. Returns matching lines with context.
    Use this BEFORE reading entire files. Much cheaper than loading files into context."""
    cmd = ["rg", "--max-count", str(max_results), "-C", "2"]
    if file_type:
        cmd.extend(["-t", file_type])
    cmd.append(pattern)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    return result.stdout[:5000]  # Cap output to prevent context bloat

@tool
def query_json(json_path: str, jq_filter: str) -> str:
    """Process JSON file with jq filter. Use for extracting specific fields
    from API responses, configs, or data files."""
    result = subprocess.run(
        ["jq", jq_filter, json_path],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout[:5000]
```

---

## Anti-patterns

| Anti-pattern | Why it's bad | What to do instead |
|---|---|---|
| **Dumping entire files into context** | A 2000-line file costs ~8000 tokens. The 20 relevant lines cost ~80 tokens. | Use `head`, `tail`, `rg -C`, or `sg` to extract relevant sections. |
| **Using LLM to parse JSON** | `jq` is instant, free, deterministic. | The LLM should generate the jq filter, not process the JSON. |
| **Regex via LLM** | LLMs hallucinate regex patterns, especially around escaping. | Use `rg -F` for literal strings. For complex regex, write a small Python script with `re` module. |
| **Embedding everything upfront** | Creates stale indexes and maintenance burden. | Just-in-time retrieval with grep/glob is simpler and works better for many codebases. |
| **Ignoring output size** | A grep matching 10,000 lines will blow the context window. | Always use `--max-count`, `head`, or truncation. |
| **Sending structured data to LLM for filtering** | "All orders where status is 'pending' and amount > 100" is a SQL query, not an LLM task. | Use `jq` filter or `sqlite3` query. |

---

## References

**Ripgrep for agents:**
- CodeAnt AI. Why Your Coding Agent Should Use ripgrep Instead of grep. https://www.codeant.ai/blogs/why-coding-agents-should-use-ripgrep
- CodeAnt AI. Why ripgrep Beats grep for Modern Code Search. https://www.codeant.ai/blogs/ripgrep-vs-grep

**Three-layer search stack:**
- Ceaksan. grep, ripgrep, and AI-Powered Text Search. https://ceaksan.com/en/grep-ripgrep-and-text-search-in-the-age-of-ai/

**ast-grep:**
- ast-grep. Using ast-grep with AI Tools. https://ast-grep.github.io/advanced/prompting.html
- ast-grep. Journey to AI Generated Rules. https://ast-grep.github.io/blog/ast-grep-agent.html
- ast-grep Claude Code skill. https://github.com/ast-grep/agent-skill

**Agent-optimized search tools:**
- Probe. https://github.com/probelabs/probe
- grepika. https://github.com/agentika-labs/grepika
- grepai. https://github.com/yoanbernabeu/grepai
- mgrep. https://github.com/mixedbread-ai/mgrep
- AI-grep. https://github.com/seqis/AI-grep
- llm_grep. https://github.com/karlkurzer/llm_grep

**Unix tools for agents:**
- Matt Westcott. Give your LLM a terminal. https://mattwestcott.org/blog/give-your-llm-a-terminal
- Yew Jin Lim. LLMs the UNIX Way. https://yewjin.substack.com/p/llms-the-unix-way
- just-bash (sandboxed bash for agents). https://justbash.dev/
- Structured text tools list. https://github.com/dbohdan/structured-text-tools
- Simon Willison. llm-tools-sqlite. https://github.com/simonw/llm-tools-sqlite

**Anthropic's tool design:**
- Anthropic. Effective Context Engineering for AI Agents. https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic. Advanced Tool Use. https://www.anthropic.com/engineering/advanced-tool-use
- Claude Code changelog (tool preference improvements). https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md

**Agent architecture:**
- Mike Mason. AI Coding Agents in 2026: Coherence Through Orchestration. https://mikemason.ca/writing/ai-coding-agents-jan-2026/

---

**See also:** `entity-resolution.md` for how text search and filtering tools fit into entity resolution blocking layers (exact key matching, sorted neighborhood, semantic similarity). `retrieval.md` for retrieval-augmented generation patterns — pre-indexed semantic search over knowledge bases and document corpora. Use text-tools for dynamic code/data search (just-in-time context); use retrieval.md patterns for static knowledge bases where pre-indexing is justified.
