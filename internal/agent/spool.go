package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"github.com/MathieuLF/gaylemon/internal/model"
)

type Spool struct {
	db *sql.DB
}

type PendingBatch struct {
	ID             string
	Stream         string
	Sequence       int64
	SourceRevision string
	Body           []byte
	Attempts       int
}

func OpenSpool(path string) (*Spool, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return nil, fmt.Errorf("création du répertoire de file: %w", err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("ouverture de la file: %w", err)
	}
	db.SetMaxOpenConns(1)
	statements := []string{
		`PRAGMA journal_mode=WAL`,
		`PRAGMA synchronous=FULL`,
		`PRAGMA busy_timeout=15000`,
		`PRAGMA wal_autocheckpoint=64`,
		`PRAGMA journal_size_limit=8388608`,
		`CREATE TABLE IF NOT EXISTS stream_sequences (stream TEXT PRIMARY KEY, sequence INTEGER NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS batches (
			id TEXT PRIMARY KEY,
			stream TEXT NOT NULL,
			sequence INTEGER NOT NULL,
			source_revision TEXT NOT NULL DEFAULT '',
			body BLOB NOT NULL,
			created_at TEXT NOT NULL,
			attempts INTEGER NOT NULL DEFAULT 0,
			last_error TEXT NOT NULL DEFAULT ''
		)`,
		`CREATE INDEX IF NOT EXISTS batches_order_idx ON batches(created_at, sequence)`,
		`CREATE TABLE IF NOT EXISTS completed_stream_revisions (
			stream TEXT PRIMARY KEY,
			source_revision TEXT NOT NULL,
			completed_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS command_results (
			command_id TEXT PRIMARY KEY,
			sequence INTEGER NOT NULL,
			status TEXT NOT NULL,
			message TEXT NOT NULL DEFAULT '',
			executed_at TEXT NOT NULL
		)`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			db.Close()
			return nil, fmt.Errorf("initialisation de la file: %w", err)
		}
	}
	var sourceRevisionColumn int
	if err := db.QueryRow(`SELECT count(*) FROM pragma_table_info('batches') WHERE name='source_revision'`).Scan(&sourceRevisionColumn); err != nil {
		db.Close()
		return nil, fmt.Errorf("inspection de la file: %w", err)
	}
	if sourceRevisionColumn == 0 {
		if _, err := db.Exec(`ALTER TABLE batches ADD COLUMN source_revision TEXT NOT NULL DEFAULT ''`); err != nil {
			db.Close()
			return nil, fmt.Errorf("mise à niveau de la file: %w", err)
		}
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS batches_revision_idx ON batches(stream, source_revision)`); err != nil {
		db.Close()
		return nil, fmt.Errorf("indexation de la file: %w", err)
	}
	return &Spool{db: db}, nil
}

func (s *Spool) CommandResult(ctx context.Context, commandID string) (model.CommandAck, bool, error) {
	var ack model.CommandAck
	err := s.db.QueryRowContext(ctx, `SELECT status, message FROM command_results WHERE command_id = ?`, commandID).Scan(&ack.Status, &ack.Message)
	if errors.Is(err, sql.ErrNoRows) {
		return model.CommandAck{}, false, nil
	}
	return ack, err == nil, err
}

func (s *Spool) SaveCommandResult(ctx context.Context, command model.Command, ack model.CommandAck) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO command_results(command_id, sequence, status, message, executed_at)
		VALUES(?, ?, ?, ?, ?) ON CONFLICT(command_id) DO NOTHING`, command.ID, command.Sequence, ack.Status, ack.Message, time.Now().UTC().Format(time.RFC3339Nano))
	return err
}

func (s *Spool) Close() error { return s.db.Close() }

func (s *Spool) Enqueue(ctx context.Context, batch *model.Batch) error {
	if batch == nil || batch.ID == "" || batch.Stream == "" {
		return errors.New("lot incomplet")
	}
	body, err := json.Marshal(batch)
	if err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if batch.Sequence <= 0 {
		if _, err := tx.ExecContext(ctx, `INSERT INTO stream_sequences(stream, sequence) VALUES(?, 0) ON CONFLICT(stream) DO NOTHING`, batch.Stream); err != nil {
			return err
		}
		if err := tx.QueryRowContext(ctx, `UPDATE stream_sequences SET sequence = sequence + 1 WHERE stream = ? RETURNING sequence`, batch.Stream).Scan(&batch.Sequence); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO batches(id, stream, sequence, source_revision, body, created_at) VALUES(?, ?, ?, ?, ?, ?)`, batch.ID, batch.Stream, batch.Sequence, batch.SourceRevision, body, time.Now().UTC().Format(time.RFC3339Nano)); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Spool) HasRevision(ctx context.Context, stream, revision string) (bool, error) {
	if revision == "" {
		return false, nil
	}
	var present int
	err := s.db.QueryRowContext(ctx, `SELECT EXISTS(
		SELECT 1 FROM batches
		 WHERE stream = ?
		   AND (source_revision = ? OR instr(source_revision, ? || ':sha256:') = 1)
		UNION ALL
		SELECT 1 FROM completed_stream_revisions
		 WHERE stream = ?
		   AND (source_revision = ? OR instr(source_revision, ? || ':sha256:') = 1)
	)`, stream, revision, revision, stream, revision, revision).Scan(&present)
	return present != 0, err
}

func (s *Spool) Peek(ctx context.Context) (PendingBatch, bool, error) {
	var pending PendingBatch
	err := s.db.QueryRowContext(ctx, `SELECT id, stream, sequence, source_revision, body, attempts FROM batches ORDER BY created_at, sequence LIMIT 1`).
		Scan(&pending.ID, &pending.Stream, &pending.Sequence, &pending.SourceRevision, &pending.Body, &pending.Attempts)
	if errors.Is(err, sql.ErrNoRows) {
		return PendingBatch{}, false, nil
	}
	if err != nil {
		return PendingBatch{}, false, err
	}
	return pending, true, nil
}

func (s *Spool) Complete(ctx context.Context, id string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var stream, revision string
	if err := tx.QueryRowContext(ctx, `SELECT stream, source_revision FROM batches WHERE id = ?`, id).Scan(&stream, &revision); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM batches WHERE id = ?`, id); err != nil {
		return err
	}
	if revision != "" {
		if _, err := tx.ExecContext(ctx, `INSERT INTO completed_stream_revisions(stream, source_revision, completed_at)
			VALUES(?, ?, ?) ON CONFLICT(stream) DO UPDATE SET source_revision=excluded.source_revision, completed_at=excluded.completed_at`,
			stream, revision, time.Now().UTC().Format(time.RFC3339Nano)); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	_, _ = s.db.ExecContext(ctx, `PRAGMA wal_checkpoint(PASSIVE)`)
	return nil
}

func (s *Spool) Fail(ctx context.Context, id string, failure error) error {
	message := ""
	if failure != nil {
		message = failure.Error()
		if len(message) > 1000 {
			message = message[:1000]
		}
	}
	_, err := s.db.ExecContext(ctx, `UPDATE batches SET attempts = attempts + 1, last_error = ? WHERE id = ?`, message, id)
	return err
}

func (s *Spool) Depth(ctx context.Context) (int64, error) {
	var depth int64
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM batches`).Scan(&depth)
	return depth, err
}
