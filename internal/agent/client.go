package agent

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
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

const compressRequestThreshold = 32 << 10

var ErrSeasonArchived = errors.New("saison archivée confirmée par le service")

type Client struct {
	config     Config
	httpClient *http.Client
	Shadow     bool
}

func NewClient(config Config) *Client {
	return &Client{config: config, httpClient: &http.Client{Timeout: config.HTTPTimeout}, Shadow: config.Shadow}
}

func (c *Client) SendBatchBody(ctx context.Context, body []byte) (model.IngestResult, int64, error) {
	path := "/api/ingest/v1/batches"
	if c.Shadow {
		path += "?shadow=1"
	}
	var result model.IngestResult
	bytesSent, err := c.sendJSON(ctx, http.MethodPost, path, body, &result)
	if err != nil {
		return result, bytesSent, err
	}
	return result, bytesSent, nil
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
	_, err := c.sendJSON(ctx, method, path, body, target)
	return err
}

func (c *Client) sendJSON(ctx context.Context, method, path string, body []byte, target any) (int64, error) {
	wireBody, contentEncoding, err := compressJSONBody(body)
	if err != nil {
		return 0, err
	}
	request, err := http.NewRequestWithContext(ctx, method, c.config.APIBaseURL+path, bytes.NewReader(wireBody))
	if err != nil {
		return 0, err
	}
	request.Header.Set("Accept", "application/json")
	if len(body) > 0 {
		request.Header.Set("Content-Type", "application/json")
	}
	if contentEncoding != "" {
		request.Header.Set("Content-Encoding", contentEncoding)
	}
	if err := auth.SignRequest(request, wireBody, c.config.AgentID, c.config.PrivateKey, time.Now().UTC()); err != nil {
		return 0, err
	}
	response, err := c.httpClient.Do(request)
	if err != nil {
		return int64(len(wireBody)), err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, 2<<20))
	if err != nil {
		return int64(len(wireBody)), err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		if response.StatusCode == http.StatusLocked {
			if err := c.verifySeasonLocked(response, responseBody, time.Now().UTC()); err != nil {
				return int64(len(wireBody)), err
			}
			return int64(len(wireBody)), ErrSeasonArchived
		}
		message := strings.TrimSpace(string(responseBody))
		if len(message) > 500 {
			message = message[:500]
		}
		return int64(len(wireBody)), fmt.Errorf("API %s: HTTP %d: %s", path, response.StatusCode, message)
	}
	if target != nil && len(responseBody) > 0 {
		if err := json.Unmarshal(responseBody, target); err != nil {
			return int64(len(wireBody)), errors.New("réponse API invalide")
		}
	}
	return int64(len(wireBody)), nil
}

func (c *Client) verifySeasonLocked(response *http.Response, body []byte, now time.Time) error {
	if response.Header.Get("X-Gaylemon-Season-State") != "archived" || len(c.config.ResponsePublicKey) != ed25519.PublicKeySize {
		return errors.New("réponse season-archived non vérifiable")
	}
	timestamp := response.Header.Get("X-Gaylemon-Response-Timestamp")
	signedAt, err := time.Parse(time.RFC3339Nano, timestamp)
	if err != nil || now.Sub(signedAt) > 5*time.Minute || signedAt.Sub(now) > 5*time.Minute {
		return errors.New("réponse season-archived expirée")
	}
	signature, err := base64.StdEncoding.DecodeString(response.Header.Get("X-Gaylemon-Response-Signature"))
	if err != nil || len(signature) != ed25519.SignatureSize {
		return errors.New("signature season-archived invalide")
	}
	digest := sha256.Sum256(body)
	message := timestamp + "\n423\n" + hex.EncodeToString(digest[:])
	if !ed25519.Verify(c.config.ResponsePublicKey, []byte(message), signature) {
		return errors.New("signature season-archived refusée")
	}
	var payload struct {
		Error string `json:"error"`
	}
	if json.Unmarshal(body, &payload) != nil || payload.Error != "season-archived" {
		return errors.New("payload season-archived invalide")
	}
	return nil
}

func compressJSONBody(body []byte) ([]byte, string, error) {
	if len(body) < compressRequestThreshold {
		return body, "", nil
	}
	var compressed bytes.Buffer
	writer, err := gzip.NewWriterLevel(&compressed, gzip.BestSpeed)
	if err != nil {
		return nil, "", err
	}
	if _, err := writer.Write(body); err != nil {
		return nil, "", err
	}
	if err := writer.Close(); err != nil {
		return nil, "", err
	}
	return compressed.Bytes(), "gzip", nil
}
