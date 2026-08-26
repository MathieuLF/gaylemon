package agent

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

type Runner struct {
	Config               Config
	Spool                *Spool
	Client               *Client
	Logger               *slog.Logger
	Version              string
	CommandDrainInterval time.Duration
}

func (r *Runner) Flush(ctx context.Context) (int, error) {
	completed := 0
	for {
		pending, found, err := r.Spool.Peek(ctx)
		if err != nil {
			return completed, err
		}
		if !found {
			return completed, nil
		}
		result, bytesSent, err := r.Client.SendBatchBody(ctx, pending.Body)
		if err != nil {
			_ = r.Spool.Fail(ctx, pending.ID, err)
			return completed, err
		}
		if err := r.Spool.Complete(ctx, pending.ID); err != nil {
			return completed, err
		}
		completed++
		r.Logger.Info("lot publié", "batch", result.BatchID, "stream", pending.Stream, "documents", result.Documents, "bytes", bytesSent)
	}
}

func (r *Runner) Run(ctx context.Context) error {
	if r.Logger == nil {
		r.Logger = slog.Default()
	}
	ticker := time.NewTicker(r.Config.PollInterval)
	defer ticker.Stop()
	var lastSuccess time.Time
	var lastError string
	var lastSequence int64
	for {
		if _, err := r.Flush(ctx); err != nil && !errors.Is(err, context.Canceled) {
			lastError = err.Error()
			r.Logger.Warn("publication reportée", "error", err)
		} else {
			lastSuccess = time.Now().UTC()
			lastError = ""
		}
		depth, _ := r.Spool.Depth(ctx)
		status := model.AgentStatus{AgentID: r.Config.AgentID, Version: r.Version, Profile: r.Config.Profile, QueueDepth: depth, LastSuccessAt: lastSuccess, LastError: lastError}
		if err := r.Client.Heartbeat(ctx, status); err != nil && !errors.Is(err, context.Canceled) {
			r.Logger.Warn("battement non transmis", "error", err)
		}
		commands, err := r.Client.Commands(ctx, lastSequence)
		if err != nil && !errors.Is(err, context.Canceled) {
			r.Logger.Warn("commandes indisponibles", "error", err)
		} else {
			executor := CommandExecutor{Helper: r.Config.CommandHelper, UseSudo: r.Config.CommandSudo}
			execute := func(commandContext context.Context, command model.Command) model.CommandAck {
				return executor.Execute(commandContext, command)
			}
			for _, command := range commands {
				ack, found, resultErr := r.Spool.CommandResult(ctx, command.ID)
				if resultErr != nil {
					r.Logger.Warn("résultat local illisible", "command", command.ID, "error", resultErr)
					break
				}
				if !found {
					if command.Kind == "season.activate" && commandTransition(command) == "activate" {
						if err := r.Spool.ResetForNewSeason(ctx); err != nil {
							ack = model.CommandAck{Status: "failed", Message: "préparation locale de la saison impossible: " + err.Error()}
						} else {
							ack = r.executeCommand(ctx, command, execute)
						}
					} else {
						ack = r.executeCommand(ctx, command, execute)
					}
					if err := r.Spool.SaveCommandResult(ctx, command, ack); err != nil {
						r.Logger.Warn("résultat local non enregistré", "command", command.ID, "error", err)
						break
					}
				}
				if err := r.Client.Ack(ctx, command.ID, ack); err != nil {
					r.Logger.Warn("acquittement reporté", "command", command.ID, "error", err)
					break
				}
				lastSequence = command.Sequence
				r.Logger.Info("commande traitée", "kind", command.Kind, "status", ack.Status)
			}
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func (r *Runner) executeCommand(ctx context.Context, command model.Command, execute func(context.Context, model.Command) model.CommandAck) model.CommandAck {
	if command.Kind != "season.archive" {
		return execute(ctx, command)
	}
	completed := make(chan model.CommandAck, 1)
	go func() { completed <- execute(ctx, command) }()
	drainInterval := r.CommandDrainInterval
	if drainInterval <= 0 {
		drainInterval = 2 * time.Second
	}
	ticker := time.NewTicker(drainInterval)
	defer ticker.Stop()
	for {
		select {
		case ack := <-completed:
			return ack
		case <-ticker.C:
			if _, err := r.Flush(ctx); err != nil && !errors.Is(err, context.Canceled) {
				r.Logger.Warn("vidage final reporté", "command", command.ID, "error", err)
			}
		case <-ctx.Done():
			return model.CommandAck{Status: "failed", Message: ctx.Err().Error()}
		}
	}
}

func commandTransition(command model.Command) string {
	var arguments struct {
		Transition string `json:"transition"`
	}
	if json.Unmarshal(command.Arguments, &arguments) != nil {
		return ""
	}
	return arguments.Transition
}
