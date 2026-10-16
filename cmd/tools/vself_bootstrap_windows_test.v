import os
import v.cmdexec

fn test_windows_self_bootstrap_links_native_helpers_and_preserves_diagnostics() ! {
	$if !windows {
		return
	}
	cc := os.find_abs_path_of_executable('gcc') or { return }
	vexe := @VEXE
	vroot := os.dir(vexe)
	root := os.join_path(os.vtmp_dir(), 'vself bootstrap helpers ${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'vc'))!
	defer { os.rmdir_all(root) or {} }
	for relative in ['vlib/time/ticks_windows.c', 'vlib/time/ticks_windows.h',
		'vlib/v/winthread_helper_windows.c', 'vlib/v/winthread_helper.h',
		'cmd/v/toolcache_windows_helpers.c', 'cmd/v/toolcache_windows_helpers.h'] {
		destination := os.join_path(root, relative)
		os.mkdir_all(os.dir(destination))!
		os.cp(os.join_path(vroot, relative), destination)!
	}
	snapshot := os.join_path(root, 'vc', 'v_win.c')
	os.write_file(snapshot, '
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#if !defined(TEST_BROKEN) && !defined(TEST_STAGE2)
unsigned long long v_time_ticks_ms(void);
void *v3_win_thread_create(size_t, void *(*)(void *), void *, unsigned int *);
int v3_win_thread_join(void *);
int v3_win_thread_is_current(unsigned int);
void *v_toolcache_create_file_w(const unsigned short *, unsigned int, unsigned int,
    unsigned int, unsigned int);
int v_toolcache_close_handle(void *);
int v_toolcache_root_is_private(const unsigned short *);
static void *worker(void *raw) { *(int *)raw = 42; return NULL; }
#endif

int wmain(int argc, wchar_t **argv) {
#ifdef TEST_BROKEN
    fputs("original self-build diagnostic\\n", stderr);
    return 7;
#else
    const wchar_t *output = NULL;
    if (argc < 2 || wcscmp(argv[argc - 1], L"cmd/v") != 0) return 2;
    for (int i = 1; i + 1 < argc; i++) {
        if (wcscmp(argv[i], L"-o") == 0) output = argv[i + 1];
    }
    if (output == NULL) return 3;
#ifdef TEST_STAGE2
    const wchar_t *input = _wgetenv(L"VSELF_TEST_FULL_CLI");
#else
    unsigned int thread_id = 0;
    int value = 0;
    if (v_time_ticks_ms() == 0) return 4;
    void *thread = v3_win_thread_create(0, worker, &value, &thread_id);
    if (thread == NULL || v3_win_thread_is_current(thread_id)) return 5;
    if (v3_win_thread_join(thread) != 0 || value != 42) return 6;
    void *handle = v_toolcache_create_file_w((const unsigned short *)argv[0],
        GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL);
    if (handle == INVALID_HANDLE_VALUE || !v_toolcache_close_handle(handle)) return 8;
    if (v_toolcache_root_is_private(L"this-directory-does-not-exist") != 0) return 9;
    const wchar_t *input = _wgetenv(L"VSELF_TEST_STAGE2");
#endif
    return input != NULL && CopyFileW(input, output, FALSE) ? 0 : 10;
#endif
}
')!
	broken := os.join_path(root, 'broken.exe')
	stage2 := os.join_path(root, 'stage2.exe')
	for kind, executable in {
		'TEST_BROKEN': broken
		'TEST_STAGE2': stage2
	} {
		build := os.exec([cc, '-std=c99', '-municode', '-D${kind}', '-o', executable, snapshot])
		assert build.exit_code == 0, build.output
	}
	tool := os.join_path(root, 'vself.exe')
	build := os.exec([vexe, '-o', tool, os.join_path(vroot, 'cmd', 'tools', 'vself.v')])
	assert build.exit_code == 0, build.output
	output := os.join_path(root, 'replacement.exe')
	env := {
		'CC':                  cc
		'VEXE':                broken
		'VFLAGS':              ''
		'VOSARGS':             ''
		'VSELF_SHOULD_FAIL':   ''
		'VSELF_COMMAND_INDEX': ''
		'VSELF_TEST_STAGE2':   stage2
		'VSELF_TEST_FULL_CLI': vexe
	}
	result := cmdexec.run_in_merged_with_env(tool, ['self', '-o', output], root, env)
	assert result.exit_code == 0, result.output
	assert result.output.contains('original self-build diagnostic'), result.output
	assert os.is_executable(output)
	version := cmdexec.run_in_merged_with_env(output, ['version'], root, env)
	assert version.exit_code == 0, version.output
	assert version.output.starts_with('V '), version.output
	assert !os.exists(os.join_path(root, '.vself_bootstrap_v1.exe'))
	assert !os.exists(os.join_path(root, '.vself_bootstrap_v2.exe'))
	// An unavailable snapshot must retain the original diagnostic as well as the
	// fallback failure, without leaving stage executables behind.
	os.rm(snapshot)!
	failure := cmdexec.run_in_merged_with_env(tool, ['self', '-o', output], root, env)
	assert failure.exit_code != 0, failure.output
	assert failure.output.contains('original self-build diagnostic'), failure.output
	assert failure.output.contains('bootstrap fallback failed:'), failure.output
	assert failure.output.contains('is missing'), failure.output
	assert !os.exists(os.join_path(root, '.vself_bootstrap_v1.exe'))
	assert !os.exists(os.join_path(root, '.vself_bootstrap_v2.exe'))
}
