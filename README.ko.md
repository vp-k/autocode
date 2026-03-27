# AutoCode

한국어 | [English](README.md)

**자율 코드 진화 프레임워크** — AI 에이전트가 밤새 코드를 최적화합니다.

[karpathy/autoresearch](https://github.com/karpathy/autoresearch)에서 영감을 받아 일반 소프트웨어 개발에 적용했습니다.

## 작동 방식

```
당신이 자는 동안, AI가 실험합니다. 아침에 일어나면 더 나은 코드가 있습니다.
```

```
AI가 아이디어 생성 → 코드 수정 → 빌드/테스트 검증 → 메트릭 측정 → keep 또는 rollback → 반복
```

AI 에이전트가 연속 루프로 실행됩니다:
1. **실험 메모리 읽기** (이전에 뭐가 됐고 뭐가 안 됐는지)
2. **최적화 아이디어 생성** (알고리즘 변경, 캐싱, 불필요 코드 제거...)
3. **코드 수정**
4. **스크립트가 자동으로 모든 것을 검증:**
   - 빌드 통과? 테스트 통과? → 하드 게이트
   - 메트릭 개선? → 변경 유지
   - 뭐든 실패? → `git reset`으로 즉시 롤백
5. **결과 로깅** 후 1번으로 돌아감

`main` 브랜치는 **절대 건드리지 않습니다**. 모든 실험은 격리된 `autocode/*` 브랜치에서 실행됩니다. 마음에 드는 것만 merge하면 됩니다.

## 안전장치

| 계층 | 보호 |
|------|------|
| **Git 브랜치 격리** | `autocode/*` 브랜치에서 실험, `main`은 그대로 |
| **하드 게이트** | 빌드/테스트 필수 통과 — 망가진 코드는 즉시 롤백 |
| **Readonly 파일** | `package.json`, 마이그레이션, `.env` 등 보호 |
| **변경량 제한** | 실험당 최대 파일/라인 수 설정 가능 |
| **위험 명령 차단** | `rm -rf /`, `curl | sh` 패턴 차단 |

## 빠른 시작

### 설치 (한 번만)

```bash
git clone https://github.com/vp-k/autocode.git
cd autocode
bash install.sh
```

### 사용 (아무 프로젝트에서)

```bash
cd your-project

# Claude Code에서:
/autocode
```

이게 전부입니다. 도구가 알아서:
1. 프로젝트 타입 감지 (Node.js, Rust, Go, Python, Docker, Java...)
2. `.autocode.yaml` 기본 설정 생성
3. 실험 루프 시작

### 수동 설정

```bash
# 설정만 생성
/autocode setup

# .autocode.yaml 커스터마이징
vim .autocode.yaml

# 실험 시작
/autocode

# 결과 확인
/autocode results

# 현재 상태 확인
/autocode status
```

## 설정 (`.autocode.yaml`)

```yaml
# 최적화 대상
target_files:
  - src/algorithm.ts

# 하드 게이트 — 모두 통과해야 함, 실패 시 즉시 롤백
gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
  - name: test
    command: "npm test"
    expect: exit_code_0

# 소프트 목표 — 가중합 점수로 keep/discard 판정
objectives:
  - name: execution_time_ms
    command: "npm run bench 2>&1"
    parse: "([0-9.]+)\\s*ms/op"
    weight: 0.8
    direction: lower    # 낮을수록 좋음
  - name: memory_kb
    command: "node -e \"console.log(process.memoryUsage().heapUsed/1024)\""
    weight: 0.2
    direction: lower

# 보호 파일 — 에이전트가 수정할 수 없음
readonly:
  - "*.test.ts"
  - "package.json"
  - "migrations/**"

# 안전 제한
changeset:
  max_files: 1
  max_lines: 100
```

## 유즈케이스 (템플릿 7종)

| 템플릿 | 메트릭 | 방향 | 예시 |
|--------|--------|------|------|
| **algo-perf** | execution_time_ms | 낮을수록 좋음 | 정렬 알고리즘 최적화 |
| **api-perf** | response_time_p95_ms | 낮을수록 좋음 | API 엔드포인트 속도 개선 |
| **bundle-size** | bundle_size_kb | 낮을수록 좋음 | 프론트엔드 번들 축소 |
| **build-time** | build_time_ms | 낮을수록 좋음 | CI 빌드 가속 |
| **docker-size** | image_size_mb | 낮을수록 좋음 | Docker 이미지 경량화 |
| **test-coverage** | coverage_pct | 높을수록 좋음 | 테스트 커버리지 증대 |
| **code-complexity** | complexity_violations | 낮을수록 좋음 | 코드 복잡도 감소 |

## 아키텍처

```
~/.claude/commands/
├── autocode.md                  # 슬래시 커맨드 (글로벌, 한 번 설치)
├── autocode-scripts/
│   ├── lib/common.sh            # 공유 라이브러리 (파서, 유틸, 보안)
│   ├── gate.sh                  # 품질 게이트 + 메트릭 측정 + 로깅
│   ├── experiment.sh            # Git 기반 실험 관리
│   ├── judge.sh                 # 자동 keep/discard 판정
│   ├── memory.sh                # 실험 메모리 자동 갱신
│   ├── setup.sh                 # 프로젝트 감지 + 설정 생성
│   └── dashboard.sh             # JSONL → HTML 대시보드
└── autocode-templates/          # 7종 유즈케이스 템플릿

your-project/                    # 프로젝트별 (자동 생성)
├── .autocode.yaml               # 프로젝트별 설정
├── .autocode/
│   ├── state.json               # 실험 상태
│   ├── memory.md                # AI가 읽는 실험 요약
│   └── logs/experiments.jsonl   # 전체 실험 로그
└── results.tsv                  # 사람이 읽는 결과 테이블
```

### 스크립트 역할

| 스크립트 | 역할 |
|---------|------|
| `gate.sh` | 게이트 실행, 메트릭 측정, 결과 로깅 |
| `experiment.sh` | Git 브랜치/커밋/롤백/상태 관리 |
| `judge.sh` | 점수 비교, keep/discard 판정 (exit 0/1) |
| `memory.sh` | 실험 로그에서 `.autocode/memory.md` 갱신 |
| `setup.sh` | 프로젝트 타입 감지, `.autocode.yaml` 생성 |
| `dashboard.sh` | 인터랙티브 HTML 보고서 생성 |

## 대시보드

실험 후 시각적 보고서 생성:

```bash
/autocode results
```

기능:
- 메트릭 추이 차트 (keep=초록, discard=빨강, crash=노랑)
- 통계 카드 (전체, 유지, 폐기, 유지율, 최고값)
- 필터링 가능한 실험 테이블
- 다크 테마, 외부 의존성 없음

## 기존 AI 도구와의 차이

| | Cursor/Copilot | Codex/Devin | **AutoCode** |
|--|---------------|-------------|-------------|
| 방식 | 사람이 주도, AI가 보조 | AI가 주도, 사람이 검토 | **AI가 실험, 결과로 증명** |
| 피드백 | 없음 (원샷) | 테스트 통과 여부 | **정량적 메트릭 개선** |
| 시간 모델 | 실시간 | 비동기 태스크 | **장시간 자율 루프** |
| 결과물 | 코드 제안 | 완성된 PR | **실험 보고서 + 최적화 코드** |
| 안전장치 | 사람 판단 | 테스트 스위트 | **Git 자동 롤백 + 하드 게이트** |

## 요구사항

- **Claude Code** (CLI)
- **bash** 4+
- **git**
- **python** (대시보드 전용)
- **jq** (권장, 필수 아님)

## 영감

- [karpathy/autoresearch](https://github.com/karpathy/autoresearch) — "AI가 밤새 ML 연구하는" 원본 패러다임
- [jung-wan-kim/autoresearch-builder](https://github.com/jung-wan-kim/autoresearch-builder) — Claude Code 플러그인 적용

## 라이선스

MIT
