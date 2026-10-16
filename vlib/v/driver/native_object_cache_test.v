module driver

import os
import v.cmdexec
import v.pref

fn native_cache_directory_worker(path string, gate chan bool) bool {
	_ := <-gate
	ensure_native_object_cache_dir(path) or { return false }
	return os.is_dir(path)
}

fn test_native_object_cache_directory_creation_is_safe_for_parallel_builds() ! {
	root := os.join_path(os.vtmp_dir(), 'native_cache_mkdir_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	for round in 0 .. 16 {
		path := os.join_path(root, 'cache_${round}')
		gate := chan bool{cap: 32}
		mut workers := []thread bool{}
		for _ in 0 .. 32 { workers << spawn native_cache_directory_worker(path, gate) }
		for _ in 0 .. 32 { gate <- true }
		results := workers.wait()
		assert results.len == 32
		assert results.all(it)
		assert os.is_dir(path)
	}
}

fn test_native_object_cache_directory_preserves_non_directory_errors() ! {
	root := os.join_path(os.vtmp_dir(), 'native_cache_not_directory_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'cache')
	os.write_file(path, 'existing file')!
	ensure_native_object_cache_dir(path) or {
		assert !os.is_dir(path)
		assert os.read_file(path)! == 'existing file'
		assert err.msg().len > 0
		return
	}
	assert false, 'a regular file must not be accepted as a cache directory'
}

fn test_windows_tcc_builds_distinct_native_objects_below_max_path() ! {
	$if !windows {
		return
	}
	compiler := os.join_path(@VEXEROOT, 'thirdparty', 'tcc', 'tcc.exe')
	if !os.is_file(compiler) {
		return
	}
	root := os.join_path(os.vtmp_dir(), 'native_object_paths_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	// A tool-cache bootstrap can leave only a few dozen characters for its native objects.
	padding := if root.len < 219 { 219 - root.len } else { 1 }
	build_dir := os.join_path(root, 'p'.repeat(padding))
	os.mkdir(build_dir)!
	object_flags := CObjectFlagPlan{ primary_compiler: compiler }
	mut stats := CObjectCacheStats{}
	mut objects := []string{}
	for name, value in {
		'first':  17
		'second': 25
	} {
		source := os.join_path(root, '${name}.c')
		os.write_file(source, 'int ${name}(void) { return ${value}; }')!
		object := compile_cached_c_source_object('${source}.o', source, '', &object_flags,
			false, false, '', [], pref.host_target(), compiler, false, build_dir, mut stats)!
		assert os.is_file(object)
		assert os.dir(object) == build_dir
		assert object.len < 260
		objects << object
	}
	assert objects[0] != objects[1]
	assert stats.temporary_objects == objects
	source := os.join_path(root, 'main.c')
	output := os.join_path(root, 'native_objects.exe')
	os.write_file(source, 'int first(void); int second(void); int main(void) { return first() + second() == 42 ? 0 : 1; }')!
	mut args := ['-o', output, source]
	args << objects
	compiled := cmdexec.run(compiler, args)
	assert compiled.exit_code == 0, compiled.output
	result := cmdexec.run(output, [])
	assert result.exit_code == 0, result.output
}
