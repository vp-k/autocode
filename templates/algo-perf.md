# AutoCode Template: Algorithm Performance Optimization

## Use Case
단일 알고리즘/함수의 실행 시간을 반복 최적화합니다.
원본 autoresearch와 가장 유사한 구조 (단일 파일 + 단일 메트릭).

## Setup Instructions

1. 최적화할 파일과 벤치마크를 준비합니다
2. 아래 `.autocode.yaml`을 프로젝트 루트에 생성합니다
3. `/autocode` 실행

## Example .autocode.yaml

```yaml
# Algorithm Performance Optimization
target_files:
  - src/algorithm.ts    # 수정할 파일

gates:
  - name: test
    command: "npm test -- --testPathPattern=algorithm"
    expect: exit_code_0
  - name: typecheck
    command: "npx tsc --noEmit"
    expect: exit_code_0

objectives:
  - name: execution_time_ms
    command: "npm run bench -- --filter=algorithm 2>&1"
    parse: "([0-9.]+)\\s*ms/op"
    weight: 1.0
    direction: lower

readonly:
  - "*.test.ts"
  - "*.spec.ts"
  - "package.json"
  - "package-lock.json"
  - "tsconfig.json"

changeset:
  max_files: 1
  max_lines: 50
```

## Strategy Guide

에이전트가 시도할 최적화 전략 순서:

1. **알고리즘 교체**: O(n^2) → O(n log n), 해시맵 활용 등
2. **데이터 구조 변경**: Array → Set/Map, LinkedList → Array
3. **캐싱/메모이제이션**: 중복 계산 제거, 결과 캐시
4. **루프 최적화**: 조기 종료, 루프 언롤링, 인덱스 최적화
5. **메모리 접근 패턴**: 캐시 친화적 순회, 메모리 프리페칭
6. **비트 연산**: 비트 마스크, 비트 시프트 활용
7. **코드 제거**: 불필요한 검증, 중복 로직 제거

## Benchmark Setup Examples

### Node.js (vitest bench)
```json
// package.json
{ "scripts": { "bench": "vitest bench" } }
```

```typescript
// src/algorithm.bench.ts
import { bench, describe } from 'vitest';
import { myAlgorithm } from './algorithm';

describe('algorithm', () => {
  bench('main', () => {
    myAlgorithm(testData);
  });
});
```

### Python (pytest-benchmark)
```bash
pip install pytest-benchmark
python -m pytest --benchmark-only --benchmark-json=bench.json
```

### Rust (cargo bench)
```bash
cargo bench -- algorithm 2>&1 | grep "time:"
```

### Go (testing.B)
```bash
go test -bench=BenchmarkAlgorithm -benchmem ./...
```
