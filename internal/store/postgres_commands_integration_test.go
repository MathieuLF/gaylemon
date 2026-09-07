//go:build integration

package store

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestCommandAndAuditAreAtomic(t *testing.T) {
	url := os.Getenv("GAYLEMON_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("GAYLEMON_TEST_DATABASE_URL absent")
	}
	ctx := context.Background()
	repo, err := OpenPostgres(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	if err := repo.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	_, err = repo.pool.Exec(ctx, `INSERT INTO gaylemon_ops.agents(agent_id) VALUES('audit-test-agent') ON CONFLICT DO NOTHING`)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.pool.Exec(ctx, `DELETE FROM gaylemon_ops.control_commands WHERE agent_id='audit-test-agent'; DELETE FROM gaylemon_ops.audit_log WHERE actor LIKE 'audit-test-%'; DELETE FROM gaylemon_ops.agents WHERE agent_id='audit-test-agent'`)
	_, err = repo.pool.Exec(ctx, `ALTER TABLE gaylemon_ops.audit_log ADD CONSTRAINT audit_test_rejection CHECK(actor <> 'audit-test-rejected')`)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.pool.Exec(ctx, `ALTER TABLE gaylemon_ops.audit_log DROP CONSTRAINT audit_test_rejection`)
	_, err = repo.EnqueueCommand(ctx, "audit-test-rejected", "audit-test-agent", "server.status", nil, "audit-test-rejected", time.Now().Add(time.Minute))
	if err == nil {
		t.Fatal("une commande sans journal ne doit pas réussir")
	}
	var count int
	if err := repo.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_ops.control_commands WHERE command_id='audit-test-rejected'`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("commande conservée après échec du journal: count=%d err=%v", count, err)
	}
	command, err := repo.EnqueueCommand(ctx, "audit-test-accepted", "audit-test-agent", "server.status", nil, "audit-test-accepted", time.Now().Add(time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if command.ID != "audit-test-accepted" {
		t.Fatalf("commande inattendue: %#v", command)
	}
	if err := repo.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_ops.audit_log WHERE actor='audit-test-accepted' AND action='command.enqueue' AND details->>'commandId'='audit-test-accepted' AND details->>'kind'='server.status'`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("journal de la commande absent: count=%d err=%v", count, err)
	}
}
