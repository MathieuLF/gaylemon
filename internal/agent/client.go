package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/internal/auth"
	"github.com/MathieuLF/gaylemon/internal/model"
)

type Client struct {
	config     Config
	httpClient *http.Client
	Shadow     bool
}

func NewClient(config Config) *Client {
	return &Client{config: config, httpClient: &http.Client{Timeout: config.HTTPTimeout}, Shadow: config.Shadow}
}

func (c *Client) SendBatch(ctx context.Context, batch model.Batch) (model.IngestResult, int64, error) {
	body, err := json.Marshal(batch)
	if err != nil {
		return model.IngestResult{}, 0, err
	}
	path := "/api/ingest/v1/batches"
	if c.Shadow {
		path += "?shadow=1"
	}
	var result model.IngestResult
	if err := c.doJSON(ctx, http.MethodPost, path, body, &result); err != nil {
		return result, int64(len(body)), err
	}
	return result, int64(len(body)), nil
}

func (c *Client) Heartbeat(ctx context.Context, status model.AgentStatus) error {
	body, err := json.Marshal(status)
	if err != nil {
		return err
	}
	return c.doJSON(ctx, http.MethodPost, "/api/agent/v1/heartbeat", body, nil)
}

func (c *Client) Commands(ctx context.Context, after int64) ([]model.Command, error) {
	var response struct {
		Commands []model.Command `json:"commands"`
	}
	path := "/api/agent/v1/commands?after=" + url.QueryEscape(strconv.FormatInt(after, 10))
	if err := c.doJSON(ctx, http.MethodGet, path, nil, &response); err != nil {
		return nil, err
	}
	return response.Commands, nil
}

func (c *Client) Ack(ctx context.Context, commandID string, ack model.CommandAck) error {
	body, err := json.Marshal(ack)
	if err != nil {
		return err
	}
	return c.doJSON(ctx, http.MethodPost, "/api/agent/v1/commands/"+url.PathEscape(commandID)+"/ack", body, nil)
}

func (c *Client) doJSON(ctx context.Context, method, path string, body []byte, target any) error {
	request, err := http.NewRequestWithContext(ctx, method, c.config.APIBaseURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Accept", "application/json")
	if len(body) > 0 {
		request.Header.Set("Content-Type", "application/json")
	}
	if err := auth.SignRequest(request, body, c.config.AgentID, c.config.PrivateKey, time.Now().UTC()); err != nil {
		return err
	}
	response, err := c.httpClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, 2<<20))
	if err != nil {
		return err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		message := strings.TrimSpace(string(responseBody))
		if len(message) > 500 {
			message = message[:500]
		}
		return fmt.Errorf("API %s: HTTP %d: %s", path, response.StatusCode, message)
	}
	if target != nil && len(responseBody) > 0 {
		if err := json.Unmarshal(responseBody, target); err != nil {
			return errors.New("réponse API invalide")
		}
	}
	return nil
}
