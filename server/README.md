# 即刻日志服务端（Go）

```bash
go run ./cmd/api                    # 默认监听 127.0.0.1:8080
bash ../scripts/go-coverage.sh      # 测试 + 覆盖率
bash ../scripts/gen-api.sh go       # 修改 api/openapi.yaml 后重新生成
golangci-lint run ./...
docker build -t jikelog-api .
```

| 接口 | 说明 |
|---|---|
| `GET /healthz` | 存活探针 |
| `GET /readyz` | 就绪探针：检查依赖，失败时返回 503 |
| `GET /api/v1/system/info` | 版本与服务器时间 |

环境变量见 [本地开发环境](../docs/部署运维/本地开发环境.md#5-服务端环境变量)，目录约定见 [架构总览](../docs/架构/总览.md#服务端目录约定)。
