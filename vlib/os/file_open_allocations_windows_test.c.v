// vtest vflags: -gc none -d track_heap -nocache
module os

#include "@VMODROOT/vlib/json2/testdata/json5_heap_tracking.h"

fn C.json5_heap_live_bytes() u64

@[manualfree]
fn test_vfopen_releases_wide_path_and_mode_on_success() {
	path := join_path(vtmp_dir(), 'vfopen_é😀_${getpid()}.txt')
	defer { rm(path) or {} }
	write_file(path, 'contents')!
	for mode in ['rb', 'wb', 'ab'] {
		before := C.json5_heap_live_bytes()
		for _ in 0 .. 100 {
			fp := vfopen(path, mode)!
			assert C.fclose(fp) == 0
		}
		assert C.json5_heap_live_bytes() == before
	}
}

@[manualfree]
fn free_expected_missing_file_error(err IError, path string) {
	assert err.code() == 2 // ENOENT
	message := err.msg()
	assert message.contains(path)
	unsafe {
		message.free()
		err.free()
	}
}

@[manualfree]
fn test_vfopen_releases_wide_path_and_mode_on_failure() {
	path := join_path(vtmp_dir(), 'vfopen_missing_é😀_${getpid()}', 'missing.txt')
	before := C.json5_heap_live_bytes()
	for _ in 0 .. 100 {
		if fp := vfopen(path, 'rb') {
			C.fclose(fp)
			assert false, 'opening a missing file should fail'
		} else {
			free_expected_missing_file_error(err, path)
		}
	}
	assert C.json5_heap_live_bytes() == before
}

@[manualfree]
fn test_open_append_releases_path_and_mode_on_success() {
	// Include forward slashes to exercise the Windows path normalization.
	path := join_path(vtmp_dir(), 'open_append_é😀_${getpid()}.txt').replace('\\', '/')
	defer { rm(path) or {} }
	write_file(path, 'before')!
	before := C.json5_heap_live_bytes()
	for _ in 0 .. 100 {
		mut file := open_append(path)!
		file.close()
	}
	assert C.json5_heap_live_bytes() == before
	mut file := open_append(path)!
	file.write_string('after')!
	file.close()
	assert read_file(path)! == 'beforeafter'
}

@[manualfree]
fn test_open_append_releases_path_and_mode_on_failure() {
	path := join_path(vtmp_dir(), 'open_append_missing_é😀_${getpid()}', 'missing.txt')
	before := C.json5_heap_live_bytes()
	for _ in 0 .. 100 {
		if mut file := open_append(path) {
			file.close()
			assert false, 'opening a file with a missing parent should fail'
		} else {
			free_expected_missing_file_error(err, path)
		}
	}
	assert C.json5_heap_live_bytes() == before
}
