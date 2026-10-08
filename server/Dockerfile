# syntax=docker/dockerfile:1
# 即刻日志 API 服务镜像（多阶段构建，运行时为非 root 用户）

FROM golang:1.27.1-alpine3.24 AS build
WORKDIR /src
# 国内构建可传入 --build-arg GOPROXY=https://goproxy.cn,direct（完整性仍由 go.sum 与 sumdb 保证）
ARG GOPROXY=https://proxy.golang.org,direct
ENV CGO_ENABLED=0 GOOS=linux GOPROXY=${GOPROXY}
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG COMMIT=dev
ARG BUILD_TIME=unknown
RUN go build -trimpath \
    -ldflags "-s -w -X github.com/vvangz/JikeLog/server/internal/version.Commit=${COMMIT} -X github.com/vvangz/JikeLog/server/internal/version.BuildTime=${BUILD_TIME}" \
    -o /out/api ./cmd/api

FROM alpine:3.24
RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S -g 10001 app && adduser -S -u 10001 -G app -H -s /sbin/nologin app
ENV TZ=Asia/Shanghai JIKELOG_ENV=production JIKELOG_HTTP_ADDR=:8080
COPY --from=build /out/api /usr/local/bin/jikelog-api
# 使用数字 UID，便于 Kubernetes runAsNonRoot 校验
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
ENTRYPOINT ["/usr/local/bin/jikelog-api"]
