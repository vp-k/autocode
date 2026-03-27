# AutoCode — 자율 코드 진화 프레임워크

## 프로젝트 개요

karpathy/autoresearch의 "자율 실험 루프" 패러다임을 코딩 분야에 적용한 Claude Code 슬래시 커맨드 플러그인.
AI 에이전트가 코드를 반복 수정하며 정량적 메트릭을 자율적으로 최적화한다.

## 핵심 패러다임

```
아이디어 생성(AI) → 코드 수정(AI) → commit → gates → measure → judge → log → memory → 반복
```

AI는 아이디어 생성과 코드 수정만 담당. 나머지는 모두 스크립트가 자동 처리.

## 프로젝트 구조

```
autoresearch/
├── CLAUDE.md                      # 이 파일
├── commands/
│   └── autocode.md                # 메인 슬래시 커맨드 (에이전트 지침, ~130줄)
├── scripts/
│   ├── lib/common.sh              # 공유 라이브러리 (파서, 유틸, 보안)
│   ├── gate.sh                    # 품질 게이트 + 메트릭 측정 + 로깅
│   ├── experiment.sh              # 실험 관리 (start/commit/discard/status)
│   ├── judge.sh                   # 자동 판정 (keep/discard, exit 0/1)
│   ├── memory.sh                  # 실험 메모리 자동 갱신
│   ├── setup.sh                   # 프로젝트 감지 + .autocode.yaml 생성
│   └── dashboard.sh               # JSONL → HTML 대시보드
├── templates/                     # 유즈케이스별 템플릿 (7종)
│   ├── algo-perf.md               # 알고리즘 성능 최적화
│   ├── api-perf.md                # API 응답시간 최적화
│   ├── bundle-size.md             # 번들 크기 최적화
│   ├── build-time.md              # 빌드 시간 최적화
│   ├── docker-size.md             # Docker 이미지 경량화
│   ├── test-coverage.md           # 테스트 커버리지 증대
│   └── code-complexity.md         # 코드 복잡도 감소
├── examples/
│   └── .autocode.yaml             # 설정 파일 예제
├── install.sh                     # Claude Code 플러그인 설치/제거
└── tests/                         # 테스트 스위트 (117개 테스트)
    ├── test_common.sh             # 공유 라이브러리 테스트 (8)
    ├── test_config.sh             # YAML 설정 파싱 테스트 (16)
    ├── test_experiment.sh         # 실험 관리 테스트 (16)
    ├── test_gate.sh               # 품질 게이트 테스트 (23)
    ├── test_judge.sh              # 판정 로직 테스트 (16)
    ├── test_memory.sh             # 메모리 갱신 테스트 (20)
    └── test_setup.sh              # 프로젝트 감지 테스트 (18)
```

## 스크립트 역할 분담

| 스크립트 | 역할 | 서브커맨드 |
|---------|------|-----------|
| `lib/common.sh` | 공유 함수 (source 전용) | — |
| `gate.sh` | 품질 게이트 + 메트릭 측정 | init, gates, measure, log, parse-config, check-readonly, summary |
| `experiment.sh` | Git 기반 실험 관리 | start, commit, discard, status |
| `judge.sh` | keep/discard 자동 판정 | (단일 커맨드, exit 0=keep, 1=discard) |
| `memory.sh` | .autocode/memory.md 갱신 | update |
| `setup.sh` | 프로젝트 초기화 | (단일 커맨드, --dry-run, --force) |
| `dashboard.sh` | HTML 보고서 생성 | (단일 커맨드) |

## 아키텍처 원칙

1. **이중 안전장치**: 하드 게이트(빌드/테스트 필수 통과) + 소프트 메트릭(가중합 점수)
2. **Git 격리**: `autocode/$TAG` 브랜치에서 실험, commit/reset으로 관리
3. **설정 기반**: YAML로 메트릭/게이트/제약 정의, 스크립트가 결정적 실행
4. **AI 최소 개입**: AI는 아이디어+코드 수정만, 나머지는 스크립트 자동화
5. **jq 비의존**: 모든 JSON 파싱은 grep/awk fallback 제공

## 코딩 컨벤션

### Bash 스크립트
- `set -euo pipefail` 필수 (common.sh 제외 — source 전용)
- 공유 함수는 `scripts/lib/common.sh`에서 source
- 함수는 `snake_case`, 변수는 `UPPER_CASE` (로컬은 `lower_case`)
- 탭 구분자 사용 (파이프 `|`는 커맨드와 충돌)
- 종료 코드: 0=성공, 1=실패, 2=설정오류, 126=보안차단

### 상태 파일
- `.autocode/state.json` — 실험 상태 (branch, experiment_id, best_score)
- `.autocode/logs/experiments.jsonl` — 실험 로그
- `.autocode/memory.md` — AI가 읽는 실험 요약
- `results.tsv` — 사람이 읽는 결과 테이블

## 설치

```bash
bash install.sh                    # ~/.claude/commands/에 설치
bash install.sh --uninstall        # 제거
bash install.sh --prefix /path     # 커스텀 경로
```

## 참조

- 원본: https://github.com/karpathy/autoresearch
- 파생: https://github.com/jung-wan-kim/autoresearch-builder
