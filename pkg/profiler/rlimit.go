// Copyright 2022 The Parca Authors
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package profiler

import (
	"fmt"
	"sync"
	"syscall"

	"golang.org/x/sys/unix"
)

var rlimitMu sync.Mutex

// BumpMemlock increases the current memlock limit to a value more reasonable for the profiler's needs.
func BumpMemlock(cur, max uint64) (syscall.Rlimit, error) {
	// TODO(kakkoyun): https://github.com/cilium/ebpf/blob/v0.8.1/rlimit/rlimit.go
	if cur == 0 {
		cur = unix.RLIM_INFINITY
	}
	if max == 0 {
		max = unix.RLIM_INFINITY
	}
	rLimit := syscall.Rlimit{
		Cur: cur, // Soft limit.
		Max: max, // Hard limit (ceiling for rlim_cur).
	}

	rlimitMu.Lock()
	// RLIMIT_MEMLOCK is 0x8.
	if err := syscall.Setrlimit(unix.RLIMIT_MEMLOCK, &rLimit); err != nil {
		rlimitMu.Unlock()
		return rLimit, fmt.Errorf("failed to increase rlimit: %w", err)
	}
	rlimitMu.Unlock()

	rLimit = syscall.Rlimit{}
	if err := syscall.Getrlimit(unix.RLIMIT_MEMLOCK, &rLimit); err != nil {
		return rLimit, fmt.Errorf("failed to get rlimit: %w", err)
	}

	return rLimit, nil
}
