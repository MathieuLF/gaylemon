package agent

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

const maxBatchContentBytes = 48 << 20

func EnqueueDirectory(ctx context.Context, spool *Spool, agentID, stream, root, prefix, revision string) ([]model.Batch, error) {
	started := time.Now()
	var documents []model.Document
	var bytesRead int64
	addFile := func(path, publicPath string) error {
		publicPath = filepath.ToSlash(strings.Trim(publicPath, "/"))
		if !validPublicPath(publicPath) {
			return fmt.Errorf("chemin public refusé: %s", publicPath)
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if !json.Valid(content) {
			return fmt.Errorf("JSON invalide: %s", path)
		}
		bytesRead += int64(len(content))
		documents = append(documents, model.Document{
			Path:        publicPath,
			Content:     json.RawMessage(content),
			CachePolicy: cachePolicy(publicPath),
		})
		return nil
	}
	info, err := os.Stat(root)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		if err := addFile(root, prefix); err != nil {
			return nil, err
		}
	} else {
		err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.IsDir() || !strings.EqualFold(filepath.Ext(entry.Name()), ".json") || strings.HasSuffix(strings.ToLower(entry.Name()), ".example.json") {
				return nil
			}
			relative, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			relative = filepath.ToSlash(relative)
			publicPath := strings.Trim(strings.TrimSpace(prefix), "/")
			if publicPath != "" {
				publicPath += "/"
			}
			publicPath += relative
			return addFile(path, publicPath)
		})
		if err != nil {
			return nil, err
		}
	}
	if len(documents) == 0 {
		return nil, errors.New("aucun document JSON à publier")
	}
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return EnqueueDocuments(ctx, spool, agentID, stream, revision, documents, model.ResourceUsage{
		DurationMS: time.Since(started).Milliseconds(), MaxRSSBytes: int64(memory.Sys), BytesRead: bytesRead,
	}, map[string]any{"sourceRoot": filepath.Base(root), "totalBytesRead": bytesRead})
}

func EnqueueDocuments(ctx context.Context, spool *Spool, agentID, stream, revision string, documents []model.Document, usage model.ResourceUsage, summary map[string]any) ([]model.Batch, error) {
	if len(documents) == 0 {
		return nil, errors.New("aucun document JSON à publier")
	}
	duplicate, err := spool.HasRevision(ctx, stream, revision)
	if err != nil {
		return nil, err
	}
	if duplicate {
		return []model.Batch{}, nil
	}
	chunks, err := documentChunks(documents, maxBatchContentBytes)
	if err != nil {
		return nil, err
	}
	batches := make([]model.Batch, 0, len(chunks))
	for index, chunk := range chunks {
		var chunkBytes int64
		for _, document := range chunk {
			chunkBytes += int64(len(document.Content))
		}
		chunkSummary := make(map[string]any, len(summary)+3)
		for key, value := range summary {
			chunkSummary[key] = value
		}
		chunkSummary["documents"] = len(chunk)
		chunkSummary["part"] = index + 1
		chunkSummary["parts"] = len(chunks)
		chunkUsage := usage
		chunkUsage.BytesRead = chunkBytes
		batchPayload := model.BatchPayload{
			Documents: chunk,
			Usage:     chunkUsage,
			Summary:   chunkSummary,
		}
		payload, err := json.Marshal(batchPayload)
		if err != nil {
			return nil, err
		}
		batch := model.Batch{ID: randomID(), AgentID: agentID, Stream: stream, SchemaVersion: 1, SourceRevision: revision, CapturedAt: time.Now().UTC(), Payload: payload}
		if err := spool.Enqueue(ctx, &batch); err != nil {
			return nil, err
		}
		batches = append(batches, batch)
	}
	return batches, nil
}

func EnqueueObservation(ctx context.Context, spool *Spool, agentID, stream, revision string, observedAt time.Time, summary map[string]any) (model.Batch, bool, error) {
	if observedAt.IsZero() {
		return model.Batch{}, false, errors.New("observation sans horodatage")
	}
	duplicate, err := spool.HasRevision(ctx, stream, revision)
	if err != nil || duplicate {
		return model.Batch{}, false, err
	}
	payload, err := json.Marshal(model.BatchPayload{Summary: summary})
	if err != nil {
		return model.Batch{}, false, err
	}
	batch := model.Batch{
		ID: randomID(), AgentID: agentID, Stream: stream, SchemaVersion: 1,
		SourceRevision: revision, CapturedAt: observedAt.UTC(), Payload: payload,
	}
	if err := spool.Enqueue(ctx, &batch); err != nil {
		return model.Batch{}, false, err
	}
	return batch, true, nil
}

func documentChunks(documents []model.Document, maxBytes int) ([][]model.Document, error) {
	var chunks [][]model.Document
	var current []model.Document
	currentBytes := 0
	for _, document := range documents {
		size := len(document.Content) + len(document.Path) + 512
		if size > maxBytes {
			return nil, fmt.Errorf("document trop volumineux pour un lot signé: %s", document.Path)
		}
		if currentBytes+size > maxBytes && len(current) > 0 {
			chunks = append(chunks, current)
			current = nil
			currentBytes = 0
		}
		current = append(current, document)
		currentBytes += size
	}
	if len(current) > 0 {
		chunks = append(chunks, current)
	}
	return chunks, nil
}

func validPublicPath(path string) bool {
	return path == "public-events-channel.json" || strings.HasPrefix(path, "data/public-") || strings.HasPrefix(path, "data/players/")
}

func cachePolicy(path string) model.CachePolicy {
	if strings.Contains(path, "/public-events-v6/") || strings.Contains(path, "/public-daily/") {
		return model.CacheImmutable
	}
	return model.CacheRevalidate
}

func randomID() string {
	raw := make([]byte, 18)
	if _, err := rand.Read(raw); err != nil {
		return fmt.Sprintf("batch-%d", time.Now().UnixNano())
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}
