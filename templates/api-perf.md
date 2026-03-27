# AutoCode Template: API Response Time Optimization

## Use Case
특정 API 엔드포인트의 p95 응답시간을 반복 최적화합니다.

## Setup Instructions

1. 벤치마크 대상 API 서버가 로컬에서 실행 가능해야 합니다
2. 벤치마크 도구(k6, wrk, ab)가 설치되어 있어야 합니다
3. 아래 `.autocode.yaml` 생성 후 `/autocode` 실행

## Example .autocode.yaml

```yaml
# API Response Time Optimization
target_files:
  - src/routes/api/target-endpoint.ts

gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
  - name: test
    command: "npm test"
    expect: exit_code_0

objectives:
  - name: response_time_p95_ms
    command: "bash scripts/bench-api.sh"
    parse: "p95=([0-9.]+)"
    weight: 0.7
    direction: lower
  - name: memory_mb
    command: "bash scripts/bench-memory.sh"
    parse: "([0-9.]+)"
    weight: 0.3
    direction: lower

readonly:
  - "*.test.ts"
  - "*.spec.ts"
  - "package.json"
  - "migrations/**"
  - "prisma/schema.prisma"

changeset:
  max_files: 3
  max_lines: 100
```

## Important: No Multiline Commands

`.autocode.yaml`의 command 필드는 **한 줄**이어야 합니다. 멀티라인 로직은 별도 스크립트 파일로 분리하세요:

```bash
# scripts/bench-api.sh
#!/usr/bin/env bash
npm start &
SERVER_PID=$!
sleep 3
k6 run --quiet scripts/bench-api.js 2>&1 | grep "p(95)" | sed 's/.*p(95)=//; s/ms.*//' | xargs -I{} echo "p95={}"
kill $SERVER_PID 2>/dev/null
```

```bash
# scripts/bench-memory.sh
#!/usr/bin/env bash
node --max-old-space-size=512 -e "require('./dist'); setTimeout(() => console.log(process.memoryUsage().heapUsed / 1024 / 1024), 5000)"
```

## Strategy Guide

1. **쿼리 최적화**: N+1 제거, 인덱스 활용, SELECT 필드 제한
2. **캐싱**: 인메모리 캐시, Redis 캐시 레이어
3. **비동기 처리**: Promise.all 병렬화, 불필요한 await 제거
4. **직렬화 최적화**: JSON 생성 최적화, 불필요한 필드 제거
5. **미들웨어 최적화**: 불필요한 미들웨어 건너뛰기
6. **연결 풀링**: DB 커넥션 풀 튜닝
7. **응답 스트리밍**: 대용량 응답 스트리밍 처리

## Benchmark Tools

### k6 (recommended)
```javascript
// scripts/bench-api.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 10,
  duration: '30s',
};

export default function () {
  const res = http.get('http://localhost:3000/api/target');
  check(res, { 'status 200': (r) => r.status === 200 });
}
```

### wrk
```bash
wrk -t4 -c50 -d30s http://localhost:3000/api/target
```
