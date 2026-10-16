module c

import os
import v.cmdexec

fn test_debugger_displays_runtime_type_names_and_method_context() {
	root := os.join_path(os.vtmp_dir(), 'debugger_runtime_types_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	source := os.join_path(root, 'main.v')
	binary := os.join_path(root, 'debugger' + $if windows { '.exe' } $else { '' })
	os.write_file(source, 'struct Counter { value int }
fn (counter Counter) inspect() {
	count := counter.value
	\$dbg;
}
fn inspect_option(optional ?int) {
	if optional != none {
		\$dbg;
	}
}
fn main() {
	a := 1
	text := "hello"
	\$dbg;
	Counter{value: 7}.inspect()
	inspect_option(9)
	println("resumed")
}
')!
	compiled := cmdexec.run(@VEXE, ['-new-compiler', '-no-retry-compilation', '-nocache', '-o',
		binary, source])
	assert compiled.exit_code == 0, compiled.output
	mut process := os.new_process(binary)
	process.set_redirect_stdio_merged()
	process.run()
	process.stdin_write('p a\np text\nc\np count\nc\np optional\nq\n')
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	assert code == 0, output
	assert output.contains('a = 1 (int)'), output
	assert output.contains('text = hello (string)'), output
	assert output.contains('Break on [main] (Counter) inspect in '), output
	assert output.contains('count = 7 (int)'), output
	assert output.contains('optional = 9 (int)'), output
	assert output.trim_space().ends_with('resumed'), output
}
