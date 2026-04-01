# AutoCode Template: Docker Image Size Optimization

## Use Case
Docker 이미지 크기를 반복 최적화합니다.

## Setup Instructions

1. Docker가 설치되어 있어야 합니다
2. 프로젝트에 Dockerfile이 있어야 합니다
3. 아래 `.autocode.yaml`을 프로젝트 루트에 생성합니다
4. `/autocode` 실행

## Example .autocode.yaml

```yaml
# Docker Image Size Optimization
target_files:
  - Dockerfile
  - .dockerignore

gates:
  - name: build
    command: "docker build -t autocode-test . --no-cache"
    expect: exit_code_0
  - name: smoke
    command: "bash scripts/docker-smoke.sh"
    expect: exit_code_0

objectives:
  - name: image_size_mb
    command: "docker image inspect autocode-test --format='{{.Size}}' | awk '{printf \"%.1f\", $1/1024/1024}'"
    parse: "([0-9.]+)"
    weight: 0.8
    direction: lower
  - name: layer_count
    command: "docker history autocode-test --no-trunc -q | wc -l"
    parse: "([0-9]+)"
    weight: 0.2
    direction: lower

readonly:
  - "src/**"
  - "*.test.*"
  - "package.json"
  - "docker-compose*.yml"

changeset:
  max_files: 2
  max_lines: 50
```

## Important: No Multiline Commands

`.autocode.yaml`의 command 필드는 **한 줄**이어야 합니다. 멀티라인 로직은 별도 스크립트 파일로 분리하세요:

```bash
# scripts/docker-smoke.sh
#!/usr/bin/env bash
docker run -d --name autocode-smoke -p 3099:3000 autocode-test
sleep 5
curl -sf http://localhost:3099/health
EXIT=$?
docker stop autocode-smoke && docker rm autocode-smoke
exit $EXIT
```

## Strategy Guide

1. **베이스 이미지**: alpine 기반, distroless, scratch
2. **멀티스테이지 빌드**: builder/runtime 분리
3. **.dockerignore**: 불필요한 파일 제외
4. **레이어 최적화**: RUN 명령 합치기, 캐시 정리
5. **의존성 최소화**: production 전용 install
6. **바이너리 최적화**: UPX 압축, strip symbols
7. **COPY 최적화**: 변경 빈도별 레이어 분리
