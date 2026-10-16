module types

import os
import v.parser
import v.pref

fn test_anonymous_struct_non_struct_embed_diagnostic_spans() {
	for newline in ['\n', '\r\n'] {
		for field in ['Int', 'Int Int'] {
			source := ['type Int = int', 'type MyIndex = struct {', '\t${field}', '}', ''].join(newline)
			path := os.join_path(os.vtmp_dir(), 'anonymous_embed_${os.getpid()}.v')
			os.write_file(path, source) or { panic(err) }
			defer { os.rm(path) or {} }
			mut p := parser.Parser.new(pref.new_preferences())
			a := p.parse_file(path)
			assert p.diagnostics.len == 0, p.diagnostics.str()
			mut tc := TypeChecker.new(a)
			tc.collect(a)
			tc.check_semantics()
			assert tc.errors.all(it.msg == 'cannot embed non-struct `Int`'), tc.errors.str()
			if field == 'Int' {
				assert tc.errors.len == 2, tc.errors.str()
				declaration_start := source.index('struct {') or { panic('missing declaration') }
				field_start := source.index('\tInt') or { panic('missing field') }
				assert tc.errors.any(it.pos.offset == declaration_start && it.pos.end == declaration_start + 'struct {'.len), tc.errors.str()
				assert tc.errors.any(it.pos.offset == field_start + 1 && it.pos.end == field_start + 4), tc.errors.str()
			} else {
				assert tc.errors.len == 1, tc.errors.str()
				type_start := source.last_index('Int') or { panic('missing type') }
				assert tc.errors[0].pos.offset == type_start, tc.errors.str()
				assert tc.errors[0].pos.end == type_start + 3, tc.errors.str()
			}
		}
	}
}
