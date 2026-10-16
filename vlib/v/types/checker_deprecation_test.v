module types

import os
import v.parser
import v.pref

fn test_deprecation_notices_format_dates_beyond_the_platform_time_range() {
	path := os.join_path(os.vtmp_dir(), 'deprecation_dates_${os.getpid()}.v')
	os.write_file(path, "module main
struct Example {}
@[deprecated: 'use another method']
@[deprecated_after: '3000-11-01']
fn (e Example) future() {}
@[deprecated]
@[deprecated_after: '3000-12-30']
fn future() {}
fn main() {
 future()
 Example{}.future()
}
") or { panic(err) }
	defer { os.rm(path) or {} }
	mut p := parser.Parser.new(pref.new_preferences())
	a := p.parse_file(path)
	assert p.diagnostics.len == 0, p.diagnostics.str()
	mut tc := TypeChecker.new(a)
	tc.collect(a)
	tc.check_semantics()
	assert tc.errors.len == 0, tc.errors.str()
	assert tc.notices.len == 2, tc.notices.str()
	assert tc.notices.any(it.msg == 'function `future` will be deprecated after 3000-12-30, and will become an error after 3001-06-28'), tc.notices.str()
	assert tc.notices.any(it.msg == 'method `Example.future` will be deprecated after 3000-11-01, and will become an error after 3001-04-30; use another method'), tc.notices.str()
}
