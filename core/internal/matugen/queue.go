package matugen

import (
	"context"
	"errors"
	"runtime"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/lowprio"
)

type Result struct {
	Success bool
	Error   error
}

type QueuedJob struct {
	Options Options
	Done    chan Result
	Ctx     context.Context
	Cancel  context.CancelFunc
}

type Queue struct {
	mu      sync.Mutex
	current *QueuedJob
	pending *QueuedJob
	jobDone chan struct{}
}

var globalQueue *Queue
var queueOnce sync.Once

func GetQueue() *Queue {
	queueOnce.Do(func() {
		globalQueue = &Queue{
			jobDone: make(chan struct{}, 1),
		}
	})
	return globalQueue
}

func (q *Queue) Submit(opts Options) <-chan Result {
	result := make(chan Result, 1)
	ctx, cancel := context.WithCancel(context.Background())

	job := &QueuedJob{
		Options: opts,
		Done:    result,
		Ctx:     ctx,
		Cancel:  cancel,
	}

	q.mu.Lock()

	if q.pending != nil {
		log.Info("Cancelling pending theme request")
		q.pending.Cancel()
		q.pending.Done <- Result{Success: false, Error: context.Canceled}
		close(q.pending.Done)
	}

	if q.current != nil {
		q.pending = job
		q.mu.Unlock()
		log.Info("Theme request queued (worker running)")
		return result
	}

	q.current = job
	q.mu.Unlock()

	go q.runWorker()
	return result
}

func (q *Queue) runWorker() {
	runtime.LockOSThread()
	lowprio.LowerThreadPriority()
	for {
		q.mu.Lock()
		job := q.current
		if job == nil {
			q.mu.Unlock()
			return
		}
		q.mu.Unlock()

		select {
		case <-job.Ctx.Done():
			q.finishJob(Result{Success: false, Error: context.Canceled})
			continue
		default:
		}

		log.Infof("Processing theme: %s %s (%s)", job.Options.Kind, job.Options.Value, job.Options.Mode)
		err := Run(job.Options)

		var result Result
		switch {
		case err == nil:
			result = Result{Success: true}
		case errors.Is(err, ErrNoChanges):
			result = Result{Success: true}
		default:
			result = Result{Success: false, Error: err}
		}

		q.finishJob(result)
	}
}

func (q *Queue) finishJob(result Result) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.current != nil {
		select {
		case q.current.Done <- result:
		default:
		}
		close(q.current.Done)
	}

	q.current = q.pending
	q.pending = nil

	if q.current == nil {
		select {
		case q.jobDone <- struct{}{}:
		default:
		}
	}
}

func (q *Queue) IsRunning() bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.current != nil
}

func (q *Queue) HasPending() bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.pending != nil
}
