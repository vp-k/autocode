# AutoCode Template: Test Coverage Optimization

## Use Case
테스트 커버리지(line/branch coverage)를 반복 최적화합니다.
기존 테스트를 개선하거나 누락된 엣지 케이스 테스트를 추가하여 커버리지를 높입니다.

## Setup Instructions

1. 프로젝트에 테스트 프레임워크와 커버리지 도구가 설정되어 있어야 합니다
2. 아래 `.autocode.yaml`을 프로젝트 루트에 생성합니다
3. `/autocode` 실행

## Example .autocode.yaml

```yaml
# Test Coverage Optimization
target_files:
  - src/
  - tests/

gates:
  - name: test
    command: "npm test -- --run"
    expect: exit_code_0

objectives:
  - name: coverage_pct
    command: "npm test -- --coverage --coverageReporters=text 2>&1"
    parse: "All files[^|]*\\|[^|]*\\|[^|]*\\|\\s*([0-9.]+)"
    weight: 1.0
    direction: higher

readonly:
  - "package.json"
  - "package-lock.json"
  - "tsconfig.json"
  - "jest.config.*"
  - "vitest.config.*"

changeset:
  max_files: 2
  max_lines: 150
```

## Important: Coverage Reporter Format

커버리지 파싱은 텍스트 리포터 출력에 의존합니다. 프레임워크별 출력 형식:

### Jest / Vitest (text reporter)
```
----------|---------|----------|---------|---------|
File      | % Stmts | % Branch | % Funcs | % Lines |
----------|---------|----------|---------|---------|
All files |   72.5  |   58.3   |   80.0  |   71.2  |
```

### pytest-cov
```yaml
objectives:
  - name: coverage_pct
    command: "python -m pytest --cov=src --cov-report=term 2>&1"
    parse: "TOTAL\\s+\\d+\\s+\\d+\\s+(\\d+)%"
    weight: 1.0
    direction: higher
```

### Go
```yaml
objectives:
  - name: coverage_pct
    command: "go test -cover ./... 2>&1"
    parse: "coverage:\\s+([0-9.]+)%"
    weight: 1.0
    direction: higher
```

## Strategy Guide

에이전트가 시도할 커버리지 향상 전략 순서:

1. **미커버 브랜치 분석**: 커버리지 리포트에서 미커버 라인/브랜치를 식별하고, 해당 경로를 실행하는 테스트 추가
2. **엣지 케이스 테스트**: 경계값, null/undefined, 빈 배열, 최대값 등 엣지 케이스 테스트 작성
3. **에러 경로 테스트**: try-catch, error handler, validation 실패 경로에 대한 테스트 추가
4. **조건문 커버리지**: if-else, switch-case의 모든 분기를 커버하는 테스트 작성
5. **모킹 전략**: 외부 의존성(DB, API, 파일시스템)을 모킹하여 접근하기 어려운 코드 경로 테스트
6. **파라미터화 테스트**: 다양한 입력 조합을 테이블 기반으로 테스트 (test.each, parametrize)
7. **통합 테스트 보강**: 단위 테스트로 커버하기 어려운 코드를 통합 테스트로 커버
