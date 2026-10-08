package httpx

import (
	"errors"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// 跨模块通用的业务错误码。
const (
	CodeValidationFailed = "VALIDATION_FAILED"
	CodeUnauthorized     = "UNAUTHORIZED"
	CodeForbidden        = "FORBIDDEN"
	CodeRateLimited      = "RATE_LIMITED"
	CodePayloadTooLarge  = "PAYLOAD_TOO_LARGE"
	CodeUnavailable      = "SERVICE_UNAVAILABLE"
)

// Error 为可直接返回给客户端的业务错误。处理器返回它时，严格处理器会将其写成对应状态码的错误信封；
// 其他错误一律视为内部错误，返回 500 且不泄露细节。
type Error struct {
	Status  int
	Code    string
	Message string
	Details map[string]any
	// RetryAfter 大于 0 时写出 Retry-After 响应头，并在 details 中给出 retryAfterSeconds。
	RetryAfter time.Duration
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

// NewError 创建业务错误。
func NewError(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

// Validation 创建参数校验错误，fields 为 {字段名: 原因}。
func Validation(fields map[string]string) *Error {
	return &Error{
		Status:  http.StatusUnprocessableEntity,
		Code:    CodeValidationFailed,
		Message: "参数校验失败",
		Details: map[string]any{"fields": fields},
	}
}

// TooManyRequests 创建频率限制错误。
func TooManyRequests(code, message string, retryAfter time.Duration) *Error {
	return &Error{Status: http.StatusTooManyRequests, Code: code, Message: message, RetryAfter: retryAfter}
}

// Unauthorized 创建未登录 / 登录失效错误。
func Unauthorized(message string) *Error {
	return NewError(http.StatusUnauthorized, CodeUnauthorized, message)
}

// WriteError 写出错误信封并终止后续处理：*Error 按其状态码写出，其他错误写成 500。
// 返回是否为业务错误，供调用方决定日志级别。
func WriteError(c *gin.Context, err error) bool {
	var appErr *Error
	if !errors.As(err, &appErr) {
		Fail(c, http.StatusInternalServerError, CodeInternal, MsgInternal)
		return false
	}
	details := appErr.Details
	if appErr.RetryAfter > 0 {
		secs := int(math.Ceil(appErr.RetryAfter.Seconds()))
		c.Header("Retry-After", strconv.Itoa(secs))
		details = withRetryAfter(details, secs)
	}
	body := ErrorBody(appErr.Code, appErr.Message)
	if len(details) > 0 {
		body.Details = &details
	}
	c.AbortWithStatusJSON(appErr.Status, Base(c, body))
	return true
}

func withRetryAfter(details map[string]any, secs int) map[string]any {
	out := make(map[string]any, len(details)+1)
	for k, v := range details {
		out[k] = v
	}
	out["retryAfterSeconds"] = secs
	return out
}
