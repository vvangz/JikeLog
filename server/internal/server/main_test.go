package server

import (
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/testinfra"
)

func TestMain(m *testing.M) {
	gin.SetMode(gin.TestMode)
	testinfra.Main(m)
}
