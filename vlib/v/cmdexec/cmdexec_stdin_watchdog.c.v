module cmdexec

fn C._Exit(code int)

fn stdin_eof_watchdog_exit(code int) {
	$if windows {
		C._exit(code)
	} $else {
		C._Exit(code)
	}
}
