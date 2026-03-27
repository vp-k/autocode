#!/usr/bin/env bash
# AutoCode Dashboard Generator
# Reads .autocode/logs/experiments.jsonl and generates an interactive HTML report
# Usage: bash dashboard.sh [--jsonl <path>] [--output <path>] [--tag <filter>]
set -euo pipefail

JSONL_FILE=".autocode/logs/experiments.jsonl"
OUTPUT_FILE="/tmp/autocode-dashboard.html"
TAG_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jsonl) JSONL_FILE="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --tag) TAG_FILTER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ ! -f "$JSONL_FILE" ]]; then
    echo "ERROR: No experiment log found at $JSONL_FILE" >&2
    exit 1
fi

# Count experiments
TOTAL=$(wc -l < "$JSONL_FILE" | tr -d ' ')
if [[ "$TOTAL" -eq 0 ]]; then
    echo "WARNING: No experiments logged yet" >&2
    exit 0
fi

# Use secure temp file instead of predictable /tmp path
TEMP_DATA=$(mktemp "${TMPDIR:-/tmp}/autocode-data.XXXXXX.json")

# Detect Python command (python3 or python)
PYTHON_CMD=""
command -v python3 >/dev/null 2>&1 && PYTHON_CMD="python3"
[[ -z "$PYTHON_CMD" ]] && command -v python >/dev/null 2>&1 && PYTHON_CMD="python"
if [[ -z "$PYTHON_CMD" ]]; then
    echo "ERROR: python3 or python not found" >&2
    exit 1
fi

# Use Python to parse JSONL and generate data for the dashboard
# Pass variables via env to prevent code injection from filenames/tags
AUTOCODE_JSONL="$JSONL_FILE" AUTOCODE_TAG="$TAG_FILTER" $PYTHON_CMD -c "
import json, sys, os

jsonl_file = os.environ['AUTOCODE_JSONL']
tag_filter = os.environ.get('AUTOCODE_TAG', '')

experiments = []
with open(jsonl_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            exp = json.loads(line)
            experiments.append(exp)
        except json.JSONDecodeError:
            continue

if tag_filter:
    experiments = [e for e in experiments if tag_filter in e.get('description', '')]

# Stats
total = len(experiments)
kept = sum(1 for e in experiments if e.get('status') == 'keep')
discarded = sum(1 for e in experiments if e.get('status') == 'discard')
crashed = sum(1 for e in experiments if e.get('status') in ('crash', 'gate_fail'))
keep_rate = (kept / total * 100) if total > 0 else 0

# Best metric (respects metric_direction from JSONL)
keep_exps = [e for e in experiments if e.get('status') == 'keep' and e.get('metric_value') is not None]
direction = experiments[0].get('metric_direction', 'lower') if experiments else 'lower'
if direction == 'higher':
    best_value = max((e['metric_value'] for e in keep_exps), default=None) if keep_exps else None
else:
    best_value = min((e['metric_value'] for e in keep_exps), default=None) if keep_exps else None
best_exp = next((e for e in keep_exps if e.get('metric_value') == best_value), None) if best_value is not None else None

# Prepare chart data
chart_data = []
for e in experiments:
    chart_data.append({
        'id': e.get('experiment_id', 0),
        'value': e.get('metric_value'),
        'status': e.get('status', 'unknown'),
        'desc': e.get('description', '')[:60],
        'strategy': e.get('strategy', ''),
        'timestamp': e.get('timestamp', ''),
        'delta_pct': e.get('delta_pct', 0),
        'cumulative_pct': e.get('cumulative_improvement_pct', 0),
    })

print(json.dumps({
    'direction': direction,
    'total': total,
    'kept': kept,
    'discarded': discarded,
    'crashed': crashed,
    'keep_rate': round(keep_rate, 1),
    'best_value': best_value,
    'best_desc': best_exp.get('description', '') if best_exp else '',
    'metric_name': experiments[0].get('metric_name', 'metric') if experiments else 'metric',
    'chart_data': chart_data,
    'experiments': [{
        'id': e.get('experiment_id', 0),
        'commit': e.get('commit', '')[:8],
        'value': e.get('metric_value'),
        'delta': e.get('delta', 0),
        'delta_pct': e.get('delta_pct', 0),
        'status': e.get('status', ''),
        'description': e.get('description', ''),
        'strategy': e.get('strategy', ''),
        'changed_files': e.get('changed_files', []),
        'changed_lines': e.get('changed_lines', 0),
        'timestamp': e.get('timestamp', ''),
        'cumulative_pct': e.get('cumulative_improvement_pct', 0),
    } for e in experiments]
}))
" > "$TEMP_DATA"

# Generate HTML
cat > "$OUTPUT_FILE" <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AutoCode Dashboard</title>
<style>
:root {
    --bg: #0a0b0f;
    --surface: #12131a;
    --surface2: #1a1b24;
    --border: #2a2b36;
    --text: #e0e0e6;
    --text-dim: #8888a0;
    --green: #4ade80;
    --red: #f87171;
    --yellow: #fbbf24;
    --blue: #60a5fa;
    --purple: #a78bfa;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: 'JetBrains Mono', 'SF Mono', 'Cascadia Code', monospace;
    background: var(--bg);
    color: var(--text);
    padding: 24px;
    line-height: 1.6;
}
h1 { font-size: 1.5em; margin-bottom: 8px; color: var(--blue); }
.subtitle { color: var(--text-dim); font-size: 0.85em; margin-bottom: 24px; }

.stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 12px;
    margin-bottom: 24px;
}
.stat-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px;
    text-align: center;
}
.stat-value { font-size: 2em; font-weight: bold; }
.stat-label { color: var(--text-dim); font-size: 0.75em; text-transform: uppercase; letter-spacing: 1px; }
.stat-value.green { color: var(--green); }
.stat-value.red { color: var(--red); }
.stat-value.yellow { color: var(--yellow); }
.stat-value.blue { color: var(--blue); }
.stat-value.purple { color: var(--purple); }

.chart-container {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px;
    margin-bottom: 24px;
}
.chart-title { font-size: 0.9em; color: var(--text-dim); margin-bottom: 12px; }
canvas { width: 100%; height: 300px; }

.table-container {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow-x: auto;
}
table { width: 100%; border-collapse: collapse; font-size: 0.8em; }
th { background: var(--surface2); color: var(--text-dim); padding: 10px 12px; text-align: left; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; font-size: 0.75em; position: sticky; top: 0; }
td { padding: 8px 12px; border-top: 1px solid var(--border); }
tr:hover { background: var(--surface2); }
.status-keep { color: var(--green); }
.status-discard { color: var(--red); }
.status-crash, .status-gate_fail { color: var(--yellow); }
.delta-pos { color: var(--green); }
.delta-neg { color: var(--red); }

.filters {
    display: flex;
    gap: 8px;
    margin-bottom: 12px;
    padding: 12px;
}
.filter-btn {
    background: var(--surface2);
    border: 1px solid var(--border);
    color: var(--text-dim);
    padding: 4px 12px;
    border-radius: 4px;
    cursor: pointer;
    font-family: inherit;
    font-size: 0.8em;
}
.filter-btn.active { border-color: var(--blue); color: var(--blue); }
.filter-btn:hover { border-color: var(--text-dim); }

.progress-bar {
    width: 100%;
    height: 4px;
    background: var(--surface2);
    border-radius: 2px;
    margin-top: 8px;
    overflow: hidden;
}
.progress-fill { height: 100%; border-radius: 2px; transition: width 0.3s; }
</style>
</head>
<body>
<h1>AutoCode Dashboard</h1>
<div class="subtitle" id="subtitle">Loading...</div>

<div class="stats" id="stats"></div>

<div class="chart-container">
    <div class="chart-title">Metric Trend</div>
    <canvas id="chart" height="300"></canvas>
</div>

<div class="table-container">
    <div class="filters" id="filters"></div>
    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>Commit</th>
                <th>Metric</th>
                <th>Delta</th>
                <th>Status</th>
                <th>Strategy</th>
                <th>Description</th>
                <th>Files</th>
                <th>Time</th>
            </tr>
        </thead>
        <tbody id="tbody"></tbody>
    </table>
</div>

<script>
HTML_HEAD

# Inject data
echo "const DATA = $(cat "$TEMP_DATA");" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" <<'HTML_SCRIPT'

// HTML escape to prevent XSS from experiment descriptions
function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// Render stats
function renderStats() {
    const s = document.getElementById('stats');
    const cards = [
        { label: 'Total', value: DATA.total, cls: 'blue' },
        { label: 'Kept', value: DATA.kept, cls: 'green' },
        { label: 'Discarded', value: DATA.discarded, cls: 'red' },
        { label: 'Crashed', value: DATA.crashed, cls: 'yellow' },
        { label: 'Keep Rate', value: DATA.keep_rate + '%', cls: 'purple' },
        { label: 'Best ' + DATA.metric_name, value: DATA.best_value ?? 'N/A', cls: 'green' },
    ];
    s.innerHTML = cards.map(c => `
        <div class="stat-card">
            <div class="stat-value ${c.cls}">${c.value}</div>
            <div class="stat-label">${c.label}</div>
        </div>
    `).join('');
    document.getElementById('subtitle').textContent =
        `${DATA.metric_name} optimization | ${DATA.total} experiments | ${new Date().toLocaleDateString()}`;
}

// Render chart
function renderChart() {
    const canvas = document.getElementById('chart');
    const ctx = canvas.getContext('2d');
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = 300 * dpr;
    ctx.scale(dpr, dpr);
    const W = rect.width, H = 300;
    const pad = { top: 20, right: 20, bottom: 30, left: 60 };

    const points = DATA.chart_data.filter(d => d.value !== null);
    if (points.length === 0) return;

    const values = points.map(d => d.value);
    const minV = Math.min(...values) * 0.95;
    const maxV = Math.max(...values) * 1.05;
    const rangeV = maxV - minV || 1;

    const xStep = (W - pad.left - pad.right) / Math.max(points.length - 1, 1);
    const toX = i => pad.left + i * xStep;
    const toY = v => pad.top + (1 - (v - minV) / rangeV) * (H - pad.top - pad.bottom);

    // Grid
    ctx.strokeStyle = '#1a1b24';
    ctx.lineWidth = 1;
    for (let i = 0; i < 5; i++) {
        const y = pad.top + i * (H - pad.top - pad.bottom) / 4;
        ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(W - pad.right, y); ctx.stroke();
        ctx.fillStyle = '#8888a0'; ctx.font = '10px monospace';
        const label = (maxV - i * rangeV / 4).toFixed(2);
        ctx.fillText(label, 4, y + 4);
    }

    // Line
    ctx.beginPath();
    ctx.strokeStyle = '#60a5fa';
    ctx.lineWidth = 2;
    points.forEach((d, i) => {
        const x = toX(i), y = toY(d.value);
        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.stroke();

    // Points
    points.forEach((d, i) => {
        const x = toX(i), y = toY(d.value);
        ctx.beginPath();
        ctx.arc(x, y, 4, 0, Math.PI * 2);
        const colors = { keep: '#4ade80', discard: '#f87171', crash: '#fbbf24', gate_fail: '#fbbf24' };
        ctx.fillStyle = colors[d.status] || '#60a5fa';
        ctx.fill();
    });
}

// Render table
let currentFilter = 'all';
function renderTable() {
    const tbody = document.getElementById('tbody');
    const exps = currentFilter === 'all'
        ? DATA.experiments
        : DATA.experiments.filter(e => e.status === currentFilter);

    tbody.innerHTML = exps.map(e => {
        // Respect metric direction: for 'lower', negative delta = good; for 'higher', positive = good
        const isGood = DATA.direction === 'higher' ? e.delta > 0 : e.delta < 0;
        const isBad = DATA.direction === 'higher' ? e.delta < 0 : e.delta > 0;
        const deltaCls = isGood ? 'delta-pos' : isBad ? 'delta-neg' : '';
        const statusCls = 'status-' + e.status;
        const files = Array.isArray(e.changed_files) ? e.changed_files.join(', ') : '';
        const time = e.timestamp ? new Date(e.timestamp).toLocaleTimeString() : '';
        return `<tr>
            <td>${e.id}</td>
            <td><code>${esc(e.commit)}</code></td>
            <td>${e.value ?? 'N/A'}</td>
            <td class="${deltaCls}">${e.delta_pct ? e.delta_pct.toFixed(1) + '%' : '-'}</td>
            <td class="${statusCls}">${esc(e.status)}</td>
            <td>${esc(e.strategy || '-')}</td>
            <td>${esc(e.description)}</td>
            <td>${esc(files || '-')}</td>
            <td>${time}</td>
        </tr>`;
    }).join('');

    // Filters
    const filters = document.getElementById('filters');
    const types = ['all', 'keep', 'discard', 'crash', 'gate_fail'];
    filters.innerHTML = types.map(t =>
        `<button class="filter-btn ${t === currentFilter ? 'active' : ''}"
                 onclick="currentFilter='${t}'; renderTable();">${t}</button>`
    ).join('');
}

renderStats();
renderChart();
renderTable();
window.addEventListener('resize', renderChart);
</script>
</body>
</html>
HTML_SCRIPT

# Cleanup
rm -f "$TEMP_DATA"

echo "Dashboard generated: $OUTPUT_FILE"
echo "Open in browser: file://$OUTPUT_FILE"
