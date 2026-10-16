module main

import os
import v.cmdexec

fn test_windows_build_checks_concrete_generic_members_before_c_compilation() {
	$if !windows {
		return
	}
	root := os.join_path(os.vtmp_dir(), 'generic_instance_build_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	source := os.join_path(root, 'main.v')
	output := os.join_path(root, 'main.exe')
	for expression in ['value.missing_field', 'value.missing_method()', "value + 'suffix'"] {
		os.write_file(source, 'fn invalid[T](value T) { println(${expression}) }\nfn main() { invalid(1) }\n') or {
			panic(err)
		}
		args := ['-new-compiler', '-no-retry-compilation', '-nocolor', '-gc', 'none', '-nocache']
		mut check_args := args.clone()
		check_args << ['-check', source]
		check := cmdexec.run(@VEXE, check_args)
		assert check.exit_code != 0, check.output
		message := match expression {
			'value.missing_field' { '`int` has no property `missing_field`' }
			'value.missing_method()' { 'missing_method' }
			else { 'operator `+` cannot concatenate `int` and `string`' }
		}
		assert check.output.contains(message), check.output
		mut build_args := args.clone()
		build_args << ['-o', output, source]
		build := cmdexec.run(@VEXE, build_args)
		assert build.exit_code != 0, build.output
		assert build.output.contains('error'), build.output
		assert build.output.contains(message), build.output
		assert !build.output.contains('C compilation error'), build.output
		if expression == 'value.missing_field' {
			opt_out := cmdexec.run_in_merged_with_env(@VEXE, build_args, root, {
				'V_CHECK_INSTANCES_IN_BUILD': '0'
			})
			assert opt_out.exit_code != 0, opt_out.output
			assert opt_out.output.contains('C compilation error'), opt_out.output
		}
	}
}

fn test_windows_build_keeps_library_generics_and_selected_comptime_branches() {
	$if !windows {
		return
	}
	root := os.join_path(os.vtmp_dir(), 'generic_instance_valid_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	source := os.join_path(root, 'main.v')
	output := os.join_path(root, 'main.exe')
	os.write_file(source, 'import arrays
fn describe[T](value T) string {
	$if T is int {
		return value.str()
	} $else {
		return value.name
	}
}
fn main() {
	chunks := arrays.chunk([41, 42], 1)
	assert chunks[0][0] == 41
	assert chunks[1][0] == 42
	assert describe(chunks[1][0]) == "42"
	println("ok")
}
') or { panic(err) }
	build := cmdexec.run_in_merged_with_env(@VEXE, ['-new-compiler', '-no-retry-compilation', '-gc',
		'none', '-nocache', '-o', output, source], root, {
		'VJOBS': '2'
	})
	assert build.exit_code == 0, build.output
	run := cmdexec.run(output, [])
	assert run.exit_code == 0, run.output
	assert run.output.trim_space() == 'ok', run.output
}
