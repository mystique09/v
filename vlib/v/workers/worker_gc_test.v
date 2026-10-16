module workers

import os

struct WorkerGcState {
mut:
	total int
}

fn worker_gc_collect_task(arg voidptr) voidptr {
	mut state := unsafe { &WorkerGcState(arg) }
	for value in 10 .. 14 {
		data := []u8{len: 4096, init: u8(value)}
		gc_collect()
		state.total += int(data[2048])
	}
	return unsafe { nil }
}

fn test_native_workers_keep_allocations_alive_during_collection() {
	previous := os.getenv_opt('V3_NO_POOL_STEAL')
	os.setenv('V3_NO_POOL_STEAL', '1', true)
	defer {
		if value := previous {
			os.setenv('V3_NO_POOL_STEAL', value, true)
		} else {
			os.unsetenv('V3_NO_POOL_STEAL')
		}
	}
	mut pool := new(2)
	defer { pool.close() }
	assert pool.stats().launch_failures == 0
	mut states := []&WorkerGcState{}
	mut tasks := []Task{}
	for _ in 0 .. 2 {
		state := &WorkerGcState{}
		states << state
		tasks << Task{ run: worker_gc_collect_task, arg: state }
	}
	assert pool.run(tasks)
	for state in states {
		assert state.total == 46
	}
	assert pool.stats().caller_run_ns == 0
}
