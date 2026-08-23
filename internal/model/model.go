package model

import (
	"encoding/json"
	"time"
)

type CachePolicy string

const (
	CacheNoStore    CachePolicy = "no-store"
	CacheRevalidate CachePolicy = "revalidate"
	CacheImmutable  CachePolicy = "immutable"
)

type Document struct {
	Path         string          `json:"path"`
	Content      json.RawMessage `json:"content"`
	CachePolicy  CachePolicy     `json:"cachePolicy"`
	GenerationID string          `json:"generationId,omitempty"`
}

type ResourceUsage struct {
	DurationMS      int64 `json:"durationMs,omitempty"`
	CPUUserMS       int64 `json:"cpuUserMs,omitempty"`
	CPUSystemMS     int64 `json:"cpuSystemMs,omitempty"`
	MaxRSSBytes     int64 `json:"maxRssBytes,omitempty"`
	IOReadBytes     int64 `json:"ioReadBytes,omitempty"`
	IOWriteBytes    int64 `json:"ioWriteBytes,omitempty"`
	BytesRead       int64 `json:"bytesRead,omitempty"`
	BytesCompressed int64 `json:"bytesCompressed,omitempty"`
	BytesSent       int64 `json:"bytesSent,omitempty"`
}

type BatchPayload struct {
	Documents []Document     `json:"documents,omitempty"`
	Usage     ResourceUsage  `json:"usage"`
	Summary   map[string]any `json:"summary,omitempty"`
}

type Batch struct {
	ID             string          `json:"batchId"`
	AgentID        string          `json:"agentId"`
	Stream         string          `json:"stream"`
	SchemaVersion  int             `json:"schemaVersion"`
	Sequence       int64           `json:"sequence"`
	SourceRevision string          `json:"sourceRevision,omitempty"`
	CapturedAt     time.Time       `json:"capturedAt"`
	Payload        json.RawMessage `json:"payload"`
	TransportBytes int64           `json:"-"`
	Compressed     bool            `json:"-"`
}

type IngestResult struct {
	BatchID        string `json:"batchId"`
	Status         string `json:"status"`
	Documents      int    `json:"documents"`
	ActiveSequence int64  `json:"activeSequence"`
}

type PublicDocument struct {
	Path        string
	Content     []byte
	CachePolicy CachePolicy
	ETag        string
	UpdatedAt   time.Time
}

type PublicEventQuery struct {
	Offset int
	Limit  int
	Type   string
	Player string
	Search string
}

type PublicEventFacet struct {
	Value string `json:"value"`
	Count int64  `json:"count"`
}

type PublicEventPage struct {
	OK            bool                          `json:"ok"`
	SchemaVersion int                           `json:"schemaVersion"`
	Source        string                        `json:"source"`
	Revision      string                        `json:"revision"`
	UpdatedAt     time.Time                     `json:"updatedAt"`
	ObservedAt    time.Time                     `json:"observedAt"`
	Freshness     string                        `json:"freshness"`
	SourceStatus  string                        `json:"sourceStatus"`
	LagSeconds    int64                         `json:"lagSeconds"`
	Offset        int                           `json:"offset"`
	Limit         int                           `json:"limit"`
	Total         int64                         `json:"total"`
	Events        []json.RawMessage             `json:"events"`
	Facets        map[string][]PublicEventFacet `json:"facets"`
	Summary       json.RawMessage               `json:"summary,omitempty"`
}

type AgentStatus struct {
	AgentID       string    `json:"agentId"`
	LastSeenAt    time.Time `json:"lastSeenAt"`
	Version       string    `json:"version"`
	Profile       string    `json:"profile"`
	QueueDepth    int64     `json:"queueDepth"`
	LastSuccessAt time.Time `json:"lastSuccessAt"`
	LastError     string    `json:"lastError,omitempty"`
}

type Command struct {
	ID          string          `json:"id"`
	Sequence    int64           `json:"sequence"`
	AgentID     string          `json:"agentId"`
	Kind        string          `json:"kind"`
	Arguments   json.RawMessage `json:"arguments,omitempty"`
	RequestedAt time.Time       `json:"requestedAt"`
	ExpiresAt   time.Time       `json:"expiresAt"`
	Status      string          `json:"status"`
}

type CommandAck struct {
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
}

type DashboardSnapshot struct {
	Agents         []AgentStatus    `json:"agents"`
	RecentRuns     []map[string]any `json:"recentRuns"`
	RecentCommands []map[string]any `json:"recentCommands"`
	DatabaseBytes  int64            `json:"databaseBytes"`
	GeneratedAt    time.Time        `json:"generatedAt"`
}
