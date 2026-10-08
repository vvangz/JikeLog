package httpx

import (
	"context"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/apigen"
)

// 通用错误码，业务模块可在各自包内定义更具体的错误码。
const (
	CodeBadRequest       = "BAD_REQUEST"
	CodeNotFound         = "NOT_FOUND"
	CodeMethodNotAllowed = "METHOD_NOT_ALLOWED"
	CodeInternal         = "INTERNAL_ERROR"
)

// 面向用户的默认错误描述。
const (
	MsgBadRequest       = "请求格式不正确"
	MsgNotFound         = "请求的资源不存在"
	MsgMethodNotAllowed = "不支持该请求方法"
	MsgInternal         = "服务器内部错误，请稍后重试"
)

// ErrorBody 构造错误体。
func ErrorBody(code, message string) *apigen.ErrorBody {
	return &apigen.ErrorBody{Code: code, Message: message}
}

// Base 构造带请求 ID 的信封公共部分。
func Base(ctx context.Context, err *apigen.ErrorBody) apigen.EnvelopeBase {
	return apigen.EnvelopeBase{Success: err == nil, Error: err, RequestId: RequestIDFrom(ctx)}
}

// Fail 写出错误信封并终止后续处理。
func Fail(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, Base(c, ErrorBody(code, message)))
}
