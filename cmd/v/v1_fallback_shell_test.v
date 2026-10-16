module main

import os

fn test_windows_fallback_make_runs_posix_recipes_with_native_paths() ! {
	$if !windows {
		return
	}
	make := find_make() or { return }
	root := os.join_path(os.vtmp_dir(), 'fallback shell ${os.getpid()}')
	os.mkdir_all(root)!
	defer {
		os.rmdir_all(root) or {}
	}
	makefile := os.join_path(root, 'Makefile')
	os.write_file(makefile, 'all:\n\t@set -e; uname -s > /dev/null; printf \'%s\\n\' "$$V1_FALLBACK_BOOTSTRAP" "$$V1_FALLBACK_CACHE_DIR" "$$V1_FALLBACK_OUTPUT"\nfail:\n\t@set -e; false; echo unexpected-success\n')!
	bootstrap := os.join_path(root, "o'connor", r'$compiler.exe')
	cache := os.join_path(root, r'$cache')
	output := os.join_path(cache, 'v1_fallback.exe')
	environment := v1_fallback_make_environment(bootstrap, cache, output)!
	assert environment.keys().filter(it.to_upper() == 'PATH') == ['PATH']
	assert environment.keys().filter(it.to_upper() == 'SHELL') == ['SHELL']
	mut process := os.new_process(make)
	process.set_args(['-f', makefile])
	process.set_environment(environment)
	process.set_redirect_stdio_merged()
	process.wait()
	result := process.stdout_slurp().replace('\r\n', '\n')
	assert process.code == 0, result
	process.close()
	assert result == [bootstrap, cache, output].map(it.replace('\\', '/')).join('\n') + '\n', result
	mut failure := os.new_process(make)
	failure.set_args(['-f', makefile, 'fail'])
	failure.set_environment(environment)
	failure.set_redirect_stdio_merged()
	failure.wait()
	failure_output := failure.stdout_slurp()
	assert failure.code != 0, failure_output
	assert !failure_output.contains('unexpected-success'), failure_output
	failure.close()
}
