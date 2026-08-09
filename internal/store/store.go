package store

import (
	"context"
	"encoding/json"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

type Session struct {
	GitHubUserID int64
	GitHubLogin  string
	CreatedAt    time.Time
	ExpiresAt    time.Time
}

type OAuthState struct {
	Verifier   string
	ReturnPath string
}

type Repository interface {
	Close()
	Ping(context.Context) error
	Migrate(context.Context) error
	ClaimNonce(context.Context, string, string, time.Time) error
	IngestBatch(context.Context, model.Batch, string, bool) (model.IngestResult, error)
	GetPublicDocument(context.Context, string) (model.PublicDocument, bool, error)
	QueryPublicEvents(context.Context, model.PublicEventQuery) (model.PublicEventPage, bool, error)
	UpsertHeartbeat(context.Context, model.AgentStatus) error
	PendingCommands(context.Context, string, int64) ([]model.Command, error)
	AckCommand(context.Context, string, string, model.CommandAck) error
	EnqueueCommand(context.Context, string, string, string, json.RawMessage, string, time.Time) (model.Command, error)
	CreateOAuthState(context.Context, string, string, string, time.Time) error
	ConsumeOAuthState(context.Context, string, time.Time) (OAuthState, error)
	CreateSession(context.Context, string, int64, string, time.Time) error
	GetSession(context.Context, string, time.Time) (Session, bool, error)
	DeleteSession(context.Context, string) error
	Dashboard(context.Context) (model.DashboardSnapshot, error)
	Maintain(context.Context) (json.RawMessage, error)
}
