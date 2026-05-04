package client

import (
	"encoding/json"
	"sync/atomic"
	"time"
)

// Stats holds atomic traffic counters.
type Stats struct {
	bytesIn       atomic.Int64
	bytesOut      atomic.Int64
	packetsIn     atomic.Int64
	packetsOut    atomic.Int64
	activeStreams  atomic.Int64
}

func (s *Stats) AddBytesIn(n int64)      { s.bytesIn.Add(n) }
func (s *Stats) AddBytesOut(n int64)     { s.bytesOut.Add(n) }
func (s *Stats) AddPacketsIn(n int64)    { s.packetsIn.Add(n) }
func (s *Stats) AddPacketsOut(n int64)   { s.packetsOut.Add(n) }
func (s *Stats) SetActiveStreams(n int64) { s.activeStreams.Store(n) }
func (s *Stats) IncActiveStreams()       { s.activeStreams.Add(1) }
func (s *Stats) DecActiveStreams()       { s.activeStreams.Add(-1) }

func (s *Stats) reset() {
	s.bytesIn.Store(0)
	s.bytesOut.Store(0)
	s.packetsIn.Store(0)
	s.packetsOut.Store(0)
	s.activeStreams.Store(0)
}

// StatsSnapshot is a plain-value snapshot for JSON serialization.
type StatsSnapshot struct {
	BytesIn      int64     `json:"bytesIn"`
	BytesOut     int64     `json:"bytesOut"`
	PacketsIn    int64     `json:"packetsIn"`
	PacketsOut   int64     `json:"packetsOut"`
	ActiveStreams int64    `json:"activeStreams"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

func (s *Stats) snapshot() StatsSnapshot {
	return StatsSnapshot{
		BytesIn:      s.bytesIn.Load(),
		BytesOut:     s.bytesOut.Load(),
		PacketsIn:    s.packetsIn.Load(),
		PacketsOut:   s.packetsOut.Load(),
		ActiveStreams: s.activeStreams.Load(),
		UpdatedAt:    time.Now().UTC(),
	}
}

func (s *Stats) toJSON() string {
	snap := s.snapshot()
	b, err := json.Marshal(snap)
	if err != nil {
		return `{"error":"marshal failed"}`
	}
	return string(b)
}
