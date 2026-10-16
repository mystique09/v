import os
import v.cmdexec

fn test_restarted_compiler_owns_fallback_diagnostics_and_exit_status() {
	clang := os.find_abs_path_of_executable('clang') or { return }
	vexe := if os.base(@VEXE) in ['v1_fallback', 'v1_fallback.exe'] {
		os.join_path(os.dir(@VEXE), 'v' + $if windows { '.exe' } $else { '' })
	} else {
		@VEXE
	}
	root := os.join_path(os.vtmp_dir(), 'v3_restart_fallback_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(os.join_path(root, 'answer.h'), 'static inline int answer(void) { return 5; }\n')!
	source := os.join_path(root, 'main.v')
	output := os.join_path(root, 'program' + $if windows { '.exe' } $else { '' })
	// A user header makes the cached Clang build restart without the cache.
	// Enable the launcher's automatic fallback even when the test runner disabled it.
	mut environment := {
		'VFLAGS':                        ''
		'VOSARGS':                       ''
		'V_MACOS_V3_NO_FALLBACK':        ''
		'V_MACOS_V3_RETRY':              ''
		'V_C_ERROR_BUG_REPORT_DISABLED': '1'
		'V3_CACHE_TRACE':                ''
	}
	args := ['-no-retry-compilation', '-cc', clang, '-o', output, 'run', source]
	for status in [0, 23] {
		os.write_file(source, 'module main\n#include "@DIR/answer.h"\nfn C.answer() int\nfn main() { println(C.answer()); exit(${status}) }\n')!
		result := cmdexec.run_in_merged_with_env(vexe, args, '', environment)
		assert result.exit_code == status, result.output
		assert result.output.replace('\r\n', '\n') == '5\n', result.output
	}
	// A real checker failure after the same restart must still be diagnosed once.
	os.write_file(source, 'module main\n#include "@DIR/answer.h"\nfn main() { missing_restart_function() }\n')!
	environment['V3_CACHE_TRACE'] = '1'
	failed := cmdexec.run_in_merged_with_env(vexe, args, '', environment)
	assert failed.exit_code != 0, failed.output
	assert failed.output.count('error: unknown function: missing_restart_function') == 1, failed.output
	assert failed.output.count('native C inputs require compilation without header inspection:') == 1, failed.output
	assert !failed.output.contains('diagnostic replay'), failed.output
	assert !failed.output.contains('retrying with'), failed.output
}
