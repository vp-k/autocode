# AutoCode Template: Code Complexity Reduction

## Use Case
코드 복잡도(cyclomatic complexity, ESLint violations 등)를 반복 최적화합니다.
기존 기능을 유지하면서 코드를 더 읽기 쉽고 유지보수하기 좋게 리팩토링합니다.

## Setup Instructions

1. ESLint 또는 유사한 정적 분석 도구가 설정되어 있어야 합니다
2. complexity 관련 규칙이 활성화되어 있어야 합니다 (`complexity`, `max-depth`, `max-lines-per-function` 등)
3. 아래 `.autocode.yaml`을 프로젝트 루트에 생성합니다
4. `/autocode` 실행

## Example .autocode.yaml

```yaml
# Code Complexity Reduction
target_files:
  - src/

gates:
  - name: test
    command: "npm test -- --run"
    expect: exit_code_0
  - name: typecheck
    command: "npx tsc --noEmit"
    expect: exit_code_0
    optional: true

objectives:
  - name: complexity_violations
    command: "npx eslint src/ --format json 2>&1"
    parse: "errorCount.*?([0-9]+)"
    weight: 1.0
    direction: lower

readonly:
  - "*.test.*"
  - "*.spec.*"
  - "package.json"
  - ".eslintrc*"
  - "eslint.config.*"

changeset:
  max_files: 3
  max_lines: 200
```

## Important: Metric Parsing Variants

프로젝트에 맞는 복잡도 메트릭을 선택하세요:

### ESLint Error Count (JSON format)
```yaml
objectives:
  - name: complexity_violations
    command: "npx eslint src/ --format json 2>&1"
    parse: "errorCount.*?([0-9]+)"
    weight: 1.0
    direction: lower
```

### ESLint Total Problems (compact format)
```yaml
objectives:
  - name: lint_problems
    command: "npx eslint src/ 2>&1 | tail -1"
    parse: "([0-9]+) problems?"
    weight: 1.0
    direction: lower
```

### Python (radon + flake8)
```yaml
objectives:
  - name: complexity_violations
    command: "flake8 src/ --max-complexity=10 --statistics 2>&1 | wc -l"
    parse: "([0-9]+)"
    weight: 0.7
    direction: lower
  - name: avg_complexity
    command: "radon cc src/ -a -nc 2>&1 | tail -1"
    parse: "Average complexity: [A-F] \\(([0-9.]+)\\)"
    weight: 0.3
    direction: lower
```

### Go (gocyclo)
```yaml
objectives:
  - name: high_complexity_funcs
    command: "gocyclo -over 10 . 2>&1 | wc -l"
    parse: "([0-9]+)"
    weight: 1.0
    direction: lower
```

## Strategy Guide

에이전트가 시도할 복잡도 감소 전략 순서:

1. **함수 분할**: 긴 함수를 단일 책임 원칙에 따라 작은 함수로 분리
2. **Early Return / Guard Clause**: 중첩된 if-else를 early return으로 평탄화
3. **전략 패턴**: 복잡한 switch-case를 전략 맵(object/Map)으로 교체
4. **루프 단순화**: 복잡한 for 루프를 map/filter/reduce 등 선언적 패턴으로 교체
5. **조건문 단순화**: 복잡한 조건식을 의미있는 이름의 변수/함수로 추출
6. **중복 제거**: 반복되는 로직을 헬퍼 함수로 추출 (DRY)
7. **매개변수 객체화**: 파라미터가 3개 이상인 함수를 옵션 객체 패턴으로 변경
