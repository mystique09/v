module c

import os
import v.cmdexec
import v.flat
import v.pref
import v.types

fn windows_core_test_gen() FlatGen {
	mut g := FlatGen.new()
	g.a = &flat.FlatAst{}
	g.target = pref.target_from('windows', 'amd64') or { panic(err) }
	return g
}

fn test_windows_translation_unit_uses_headers_only_when_requested() {
	mut bare := windows_core_test_gen()
	bare.emit_translation_unit_include_directives()
	assert !bare.sb.str().contains('#include')
	mut headed := windows_core_test_gen()
	headed.add_c_directive('main', '#include <windows.h>', false)
	headed.emit_translation_unit_include_directives()
	assert headed.sb.str().count('#include <windows.h>') == 1
}

fn test_windows_atomic_compatibility_uses_sdk_owned_types() {
	for compiler in ['tinyc', 'tcc', 'C:/toolchain/tcc.exe', 'msvc'] {
		mut g := windows_core_test_gen()
		g.ccompiler = compiler
		g.preamble()
		code := g.sb.str()
		assert code.contains('#include <windows.h>'), compiler
		assert !code.contains('typedef u32 DWORD;'), compiler
	}
}

fn test_windows_atomic_sdk_selection_preserves_headerless_modes() {
	for compiler in ['tinyc', 'msvc'] {
		mut bootstrap := windows_core_test_gen()
		bootstrap.ccompiler = compiler
		bootstrap.output_cross_c = true
		bootstrap.compile_defines = ['v3_headerless_bootstrap']
		assert !bootstrap.c_directives_use_system_libc(), compiler
		mut target_libc := windows_core_test_gen()
		target_libc.ccompiler = compiler
		target_libc.target_libc_headers = true
		assert !target_libc.c_directives_use_system_libc(), compiler
	}
	for compiler in ['gcc', 'clang'] {
		mut g := windows_core_test_gen()
		g.ccompiler = compiler
		assert !g.c_directives_use_system_libc(), compiler
	}
}

fn test_windows_atomic_manual_header_preflight_matches_compiler() {
	mut ast := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&ast)
	mut prefs := pref.new_preferences()
	prefs.target = pref.target_from('windows', 'amd64') or { panic(err) }
	for compiler in ['tinyc', 'tcc', 'C:/toolchain/tcc.exe', 'msvc', 'gcc', 'clang'] {
		prefs.ccompiler = compiler
		assert uses_manual_stdlib_c_headers(&ast, &tc, prefs, [], false) == (compiler !in [
			'gcc',
			'clang',
		]), compiler
	}
}

fn test_windows_tcc_builds_program_without_explicit_headers() {
	$if !windows {
		return
	}
	tcc := os.join_path(@VEXEROOT, 'thirdparty', 'tcc', 'tcc.exe')
	if !os.is_file(tcc) {
		return
	}
	root := os.join_path(os.vtmp_dir(), 'windows_tcc_atomic_sdk_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	source := os.join_path(root, 'main.v')
	os.write_file(source, "fn main() {\nvalues := [1, 2, 3]\nassert values.len == 3\nprintln('ok')\n}\n")!
	executable := os.join_path(root, 'main.exe')
	compiled := cmdexec.run(@VEXE, ['-new-compiler', '-nocache', '-no-retry-compilation', '-gc',
		'none', '-cc', tcc, '-o', executable, source])
	assert compiled.exit_code == 0, compiled.output
	ran := cmdexec.run(executable, [])
	assert ran.exit_code == 0, ran.output
	assert ran.output.trim_space() == 'ok', ran.output
}

fn test_windows_core_records_match_native_sdk() {
	cc_name := $if windows { 'gcc' } $else { 'x86_64-w64-mingw32-gcc' }
	cc := os.find_abs_path_of_executable(cc_name) or { return }
	records := {
		'ULARGE_INTEGER':           ['LowPart', 'HighPart', 'QuadPart']
		'FILETIME':                 ['dwLowDateTime', 'dwHighDateTime']
		'SYSTEM_INFO':              ['dwOemId', 'wProcessorArchitecture', 'wReserved', 'dwPageSize',
			'lpMinimumApplicationAddress', 'lpMaximumApplicationAddress', 'dwActiveProcessorMask',
			'dwNumberOfProcessors', 'dwProcessorType', 'dwAllocationGranularity', 'wProcessorLevel',
			'wProcessorRevision']
		'MEMORYSTATUS':             ['dwLength', 'dwMemoryLoad', 'dwTotalPhys', 'dwAvailPhys',
			'dwTotalPageFile', 'dwAvailPageFile', 'dwTotalVirtual', 'dwAvailVirtual']
		'MEMORY_BASIC_INFORMATION': ['BaseAddress', 'AllocationBase', 'AllocationProtect', 'RegionSize',
			'State', 'Protect', 'Type']
		'PROCESS_MEMORY_COUNTERS':  ['cb', 'PageFaultCount', 'PeakWorkingSetSize', 'WorkingSetSize',
			'QuotaPeakPagedPoolUsage', 'QuotaPagedPoolUsage', 'QuotaPeakNonPagedPoolUsage',
			'QuotaNonPagedPoolUsage', 'PagefileUsage', 'PeakPagefileUsage']
	}
	mut lines := []string{}
	for name, _ in records {
		lines << '#define ${name} SDK_${name}\n#define _${name} SDK__${name}'
	}
	lines << '#include <windows.h>\n#include <psapi.h>\n#include <stdint.h>\n#include <stddef.h>'
	for name, _ in records {
		lines << '#undef ${name}\n#undef _${name}'
	}
	lines << 'typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;'
	mut g := windows_core_test_gen()
	g.headerless_windows_core_declarations()
	lines << g.sb.str()
	for name, fields in records {
		lines << '_Static_assert(sizeof(${name}) == sizeof(SDK_${name}), "${name} size");'
		lines << '_Static_assert(_Alignof(${name}) == _Alignof(SDK_${name}), "${name} alignment");'
		for field in fields {
			lines << '_Static_assert(offsetof(${name}, ${field}) == offsetof(SDK_${name}, ${field}), "${name}.${field} offset");'
			lines << '_Static_assert(sizeof(((${name}*)0)->${field}) == sizeof(((SDK_${name}*)0)->${field}), "${name}.${field} width");'
		}
	}
	lines << '#ifdef _WIN64\n_Static_assert(offsetof(MEMORY_BASIC_INFORMATION, PartitionId) == offsetof(SDK_MEMORY_BASIC_INFORMATION, PartitionId), "PartitionId offset");\n_Static_assert(sizeof(((MEMORY_BASIC_INFORMATION*)0)->PartitionId) == sizeof(((SDK_MEMORY_BASIC_INFORMATION*)0)->PartitionId), "PartitionId width");\n#endif'
	dir := os.join_path(os.vtmp_dir(), 'windows_core_sdk_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	source := os.join_path(dir, 'sdk.c')
	os.write_file(source, lines.join('\n'))!
	result := os.execute('${os.quoted_path(cc)} -std=gnu11 -fsyntax-only ${os.quoted_path(source)}')
	assert result.exit_code == 0, result.output
}

fn test_windows_native_callback_thunks_match_sdk_calling_conventions() {
	cc_name := $if windows { 'gcc' } $else { 'x86_64-w64-mingw32-gcc' }
	cc := os.find_abs_path_of_executable(cc_name) or { return }
	dir := os.join_path(os.vtmp_dir(), 'windows_core_thunks_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	for arch_flags in ['', '-m32'] {
		for name in ['vlib/builtin/core_windows.c', 'vlib/sync/thread_helper.c'] {
			source := os.join_path(@VEXEROOT, name)
			object := os.join_path(dir, 'helper.o')
			result := os.execute('${os.quoted_path(cc)} ${arch_flags} -std=gnu11 -Werror=implicit-function-declaration -Werror=incompatible-pointer-types -c ${os.quoted_path(source)} -o ${os.quoted_path(object)}')
			assert result.exit_code == 0, result.output
		}
	}
}

fn test_windows_sdk_owns_metadata_handle_declarations() {
	for arch in ['x86', 'amd64'] {
		mut g := windows_core_test_gen()
		g.set_target(pref.target_from('windows', arch) or { panic(err) })
		assert g.c_extern_calling_convention('GetFileInformationByHandle') == 'WINAPI'
		assert g.should_emit_c_extern_decl('GetFileInformationByHandle')
		g.add_c_directive('main', '#include <windows.h>', false)
		assert !g.should_emit_c_extern_decl('GetFileInformationByHandle')
	}
}

fn test_portable_windows_helpers_link_without_checkout_objects() ! {
	cc_name := $if windows { 'gcc' } $else { 'x86_64-w64-mingw32-gcc' }
	cc := os.find_abs_path_of_executable(cc_name) or { return }
	root := os.join_path(os.vtmp_dir(), 'portable_windows_helpers_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut g := windows_core_test_gen()
	g.set_output_cross_c(true)
	g.portable_windows_runtime_helpers()
	code := g.sb.str()
	for name in ['v_builtin_windows_stream', 'v_builtin_windows_debugbreak',
		'v_set_unhandled_exception_filter', 'v_time_ticks_ms', 'v3_win_thread_create',
		'v3_win_thread_join', 'v3_win_thread_is_current', 'v_toolcache_move_file_ex_w',
		'v_toolcache_create_file_w', 'v_toolcache_get_file_information', 'v_toolcache_close_handle',
		'v_toolcache_file_is_disk', 'v_toolcache_read_file', 'v_toolcache_root_is_private'] {
		assert g.inlined_c_declared_fns[name], name
	}
	source := os.join_path(root, 'helpers.c')
	os.write_file(source, code + '\nint main(void) { return v_builtin_windows_stream(1) == 0 || v_time_ticks_ms() == 0; }\n')!
	// Compile the emitted text after moving it away from the checkout. The SDK
	// supplies platform declarations, and every native definition travels with it.
	moved := os.join_path(root, 'relocated.c')
	os.mv(source, moved)!
	result := os.exec([cc, '-std=gnu11', '-Werror=implicit-function-declaration',
		'-Werror=incompatible-pointer-types', '-o', os.join_path(root, 'helpers.exe'), moved,
		'-ladvapi32'])
	assert result.exit_code == 0, result.output
}
