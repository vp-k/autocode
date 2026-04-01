# AutoCode Template: Build Time Optimization

## Use Case
프로젝트 빌드/컴파일 시간을 반복 최적화합니다.

## Setup Instructions

1. 프로젝트에 빌드 스크립트(`npm run build`)가 설정되어 있어야 합니다
2. 아래 `.autocode.yaml`을 프로젝트 루트에 생성합니다
3. `/autocode` 실행

## Example .autocode.yaml

```yaml
# Build Time Optimization
target_files:
  - tsconfig.json       # or webpack.config.js, vite.config.ts
  - vite.config.ts

gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
  - name: test
    command: "npm test -- --run"
    expect: exit_code_0
    optional: true

objectives:
  - name: build_time_ms
    command: "bash scripts/bench-build.sh"
    parse: "build_time=([0-9]+)ms"
    weight: 1.0
    direction: lower

readonly:
  - "src/**"
  - "*.test.*"
  - "package.json"
  - "package-lock.json"

changeset:
  max_files: 3
  max_lines: 50
```

## Important: No Multiline Commands

`.autocode.yaml`의 command 필드는 **한 줄**이어야 합니다. 멀티라인 로직은 별도 스크립트로 분리:

```bash
# scripts/bench-build.sh
#!/usr/bin/env bash
rm -rf node_modules/.cache dist/ .tsbuildinfo
START=$(date +%s%N)
npm run build 2>&1
END=$(date +%s%N)
echo "build_time=$(( (END - START) / 1000000 ))ms"
```

## Strategy Guide

1. **TypeScript 설정**: `skipLibCheck`, `incremental`, `composite`
2. **Bundler 설정**: esbuild/SWC 트랜스파일러, 캐시 활성화
3. **경로 최적화**: resolve.alias, resolve.extensions 최소화
4. **병렬 처리**: thread-loader, parallel compilation
5. **소스맵 최적화**: 개발용은 `cheap-module-source-map`
6. **의존성 외부화**: `externals`, `rollupOptions.external`
7. **환경 분리**: dev/prod 설정 분리로 불필요한 플러그인 제거
