module transform

import os
import v.gen.c as cgen
import v.parser
import v.pref
import v.types

fn test_cast_of_unsafe_match_materializes_propagated_values() {
	source := 'fn outcome() !int { return 42 }
fn choose(input ?bool) !i64 {
	value := if flag := input {
		i64(unsafe {
			match flag {
				true { outcome()! }
				false { outcome()! }
			}
		})
	} else {
		i64(0)
	}
	return value
}
fn main() {}
'
	generated := value_branch_c_source(source, {
		'main':    true
		'choose':  true
		'outcome': true
	})
	assert !generated.contains('?  : '), generated
	assert generated.count('= outcome();') == 2, generated
}

fn test_index_base_precedes_propagating_direct_and_nested_match() {
	source := 'fn values() []int { return [10, 20] }
fn position() !int { return 0 }
fn choose(flag bool) !int {
	return values()[match flag {
		true { position()! }
		false { position()! }
	}]
}
fn choose_nested(flag bool) !int {
	return values()[1 + (match flag {
		true { position()! }
		false { position()! }
	})]
}
fn main() {}
'
	generated := value_branch_c_source(source, {
		'main':          true
		'choose':        true
		'choose_nested': true
		'values':        true
		'position':      true
	})
	for name in ['choose', 'choose_nested'] {
		body := generated.all_after(' ${name}(bool flag) {').all_before('\n}\n')
		base_call := body.index('values()') or { panic(body) }
		index_call := body.index('position()') or { panic(body) }
		assert base_call < index_call, body
		assert body.count('values()') == 1, body
	}
}

fn value_branch_c_source(source string, used_fns map[string]bool) string {
	path := os.join_path(os.vtmp_dir(), 'value_branch_operand_${os.getpid()}.v')
	os.write_file(path, source) or { panic(err) }
	defer { os.rm(path) or {} }
	mut p := parser.Parser.new(pref.new_preferences())
	mut a := p.parse_file(path)
	mut tc := types.TypeChecker.new(a)
	tc.collect(a)
	tc.check_semantics()
	assert tc.errors.len == 0, tc.errors.str()
	mut t := new_transformer(mut a, &tc, map[string]bool{})
	t.cur_module = 'main'
	t.cur_file = path
	t.transformed_fns = []bool{len: a.nodes.len}
	t.prepare()
	t.transform_all()
	assert t.monomorph_errors.len == 0, t.monomorph_errors.str()
	mut gen := cgen.FlatGen.new()
	return gen.gen_with_used(a, used_fns, &tc)
}
