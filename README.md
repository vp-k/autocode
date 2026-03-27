# AutoCode

[한국어](README.ko.md) | English

**Autonomous Code Evolution Framework** — AI agent that optimizes your code overnight.

Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch), adapted for general software development.

## How It Works

```
You sleep. AI experiments. You wake up to better code.
```

```
AI generates idea → modifies code → build/test gate → measure metric → keep or rollback → repeat
```

The AI agent runs in a continuous loop:
1. **Reads experiment memory** (what worked, what failed before)
2. **Generates an optimization idea** (algorithm change, caching, code elimination...)
3. **Modifies your code**
4. **Scripts verify everything automatically:**
   - Build passes? Test passes? → Hard gate
   - Metric improved? → Keep the change
   - Anything fails? → Instant rollback via `git reset`
5. **Logs results** and goes back to step 1

Your `main` branch is **never touched**. All experiments run on an isolated `autocode/*` branch. You merge only what you like.

## Safety

| Layer | Protection |
|-------|-----------|
| **Git branch isolation** | Experiments run on `autocode/*` branch, `main` stays clean |
| **Hard gates** | Build/test must pass — broken code is instantly rolled back |
| **Readonly files** | `package.json`, migrations, `.env` etc. are protected |
| **Changeset limits** | Max files and lines per experiment are configurable |
| **Dangerous command blocking** | `rm -rf /`, `curl | sh` patterns are blocked |

## Quick Start

### Install (one time)

```bash
git clone https://github.com/vp-k/autocode.git
cd autocode
bash install.sh
```

### Use (in any project)

```bash
cd your-project

# In Claude Code:
/autocode
```

That's it. The tool:
1. Detects your project type (Node.js, Rust, Go, Python, Docker, Java...)
2. Generates `.autocode.yaml` with sensible defaults
3. Starts the experiment loop

### Manual setup

```bash
# Generate config only
/autocode setup

# Edit .autocode.yaml to customize gates/metrics
vim .autocode.yaml

# Start experiments
/autocode

# Check results
/autocode results

# Check current status
/autocode status
```

## Configuration (`.autocode.yaml`)

```yaml
# What to optimize
target_files:
  - src/algorithm.ts

# Hard gates — ALL must pass, or change is rolled back
gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
  - name: test
    command: "npm test"
    expect: exit_code_0

# Soft objectives — weighted composite score determines keep/discard
objectives:
  - name: execution_time_ms
    command: "npm run bench 2>&1"
    parse: "([0-9.]+)\\s*ms/op"
    weight: 0.8
    direction: lower    # lower is better
  - name: memory_kb
    command: "node -e \"console.log(process.memoryUsage().heapUsed/1024)\""
    weight: 0.2
    direction: lower

# Protected files — agent cannot modify these
readonly:
  - "*.test.ts"
  - "package.json"
  - "migrations/**"

# Safety limits
changeset:
  max_files: 1
  max_lines: 100
```

## Use Cases (Templates)

| Template | Metric | Direction | Example |
|----------|--------|-----------|---------|
| **algo-perf** | execution_time_ms | lower | Optimize sorting algorithm |
| **api-perf** | response_time_p95_ms | lower | Speed up API endpoints |
| **bundle-size** | bundle_size_kb | lower | Reduce frontend bundle |
| **build-time** | build_time_ms | lower | Speed up CI builds |
| **docker-size** | image_size_mb | lower | Shrink Docker images |
| **test-coverage** | coverage_pct | higher | Increase test coverage |
| **code-complexity** | complexity_violations | lower | Reduce cyclomatic complexity |

## Architecture

```
~/.claude/commands/
├── autocode.md                  # Slash command (global, installed once)
├── autocode-scripts/
│   ├── lib/common.sh            # Shared library (parsers, utils, security)
│   ├── gate.sh                  # Quality gates + metric measurement + logging
│   ├── experiment.sh            # Git-based experiment management
│   ├── judge.sh                 # Automatic keep/discard decision
│   ├── memory.sh                # Experiment memory auto-update
│   ├── setup.sh                 # Project detection + config generation
│   └── dashboard.sh             # JSONL → HTML dashboard
└── autocode-templates/          # 7 use-case templates

your-project/                    # Per-project (auto-generated)
├── .autocode.yaml               # Project-specific config
├── .autocode/
│   ├── state.json               # Experiment state
│   ├── memory.md                # AI reads this for context
│   └── logs/experiments.jsonl   # Full experiment log
└── results.tsv                  # Human-readable results
```

### Script Responsibilities

| Script | Role |
|--------|------|
| `gate.sh` | Run gates, measure metrics, log results |
| `experiment.sh` | Git branch/commit/discard/status |
| `judge.sh` | Compare scores, decide keep/discard (exit 0/1) |
| `memory.sh` | Update `.autocode/memory.md` from experiment logs |
| `setup.sh` | Detect project type, generate `.autocode.yaml` |
| `dashboard.sh` | Generate interactive HTML report |

## Dashboard

After experiments, generate a visual report:

```bash
/autocode results
```

Features:
- Metric trend chart (keep=green, discard=red, crash=yellow)
- Statistics cards (total, kept, discarded, keep rate, best)
- Filterable experiment table
- Dark theme, no external dependencies

## How It Differs from Other AI Tools

| | Cursor/Copilot | Codex/Devin | **AutoCode** |
|--|---------------|-------------|-------------|
| Mode | Human-driven, AI assists | AI-driven, human reviews | **AI experiments, results prove** |
| Feedback | None (one-shot) | Test pass/fail | **Quantitative metric improvement** |
| Time model | Real-time | Async task | **Long-running autonomous loop** |
| Output | Code suggestion | Completed PR | **Experiment report + optimized code** |
| Safety | Human judgment | Test suite | **Git auto-rollback + hard gates** |

## Requirements

- **Claude Code** (CLI)
- **bash** 4+
- **git**
- **python** (for dashboard only)
- **jq** (recommended, not required)

## Inspired By

- [karpathy/autoresearch](https://github.com/karpathy/autoresearch) — the original "AI does ML research overnight" paradigm
- [jung-wan-kim/autoresearch-builder](https://github.com/jung-wan-kim/autoresearch-builder) — Claude Code plugin adaptation

## License

MIT
