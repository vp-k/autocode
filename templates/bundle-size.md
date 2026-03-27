# AutoCode Template: Bundle Size Optimization

## Use Case
웹 프론트엔드 프로젝트의 빌드 번들 크기를 반복 최적화합니다.

## Example .autocode.yaml

```yaml
# Bundle Size Optimization
target_files:
  - src/index.ts
  - vite.config.ts    # or webpack.config.js

gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
  - name: test
    command: "npm test -- --run"
    expect: exit_code_0
  - name: typecheck
    command: "npx tsc --noEmit"
    expect: exit_code_0
    optional: true

objectives:
  - name: bundle_size_kb
    command: "du -sb dist/ | cut -f1 | awk '{printf \"%.1f\", $1/1024}'"
    parse: "([0-9.]+)"
    weight: 0.7
    direction: lower
  - name: gzip_size_kb
    command: "find dist/ -name '*.js' -exec gzip -c {} \\; | wc -c | awk '{printf \"%.1f\", $1/1024}'"
    parse: "([0-9.]+)"
    weight: 0.3
    direction: lower

readonly:
  - "*.test.*"
  - "*.spec.*"
  - "package.json"
  - "package-lock.json"
  - "public/**"

changeset:
  max_files: 5
  max_lines: 100
```

## Strategy Guide

1. **Dynamic Import**: 라우트별 코드 분할, lazy loading
2. **Tree Shaking**: barrel export 제거, side-effect 마킹
3. **의존성 교체**: 경량 대안 라이브러리 (moment→dayjs, lodash→lodash-es)
4. **이미지 최적화**: WebP 변환, SVG 인라인
5. **CSS 최적화**: 미사용 CSS 제거, CSS-in-JS 최적화
6. **빌드 설정**: minification, compression, sourcemap 분리
7. **코드 제거**: 미사용 export, dead code 제거
