module transform

import v.flat
import v.types

fn test_type_aliases_with_short_name_keeps_alias_order() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	tc.type_aliases.set_id('foo.Id', flat.source_type_int)
	tc.type_aliases.set_id('Other', flat.source_type_string)
	tc.type_aliases.set_id('Id', flat.source_type_u64)
	tc.type_aliases.set_id('bar.Id', flat.source_type_id('shared Store'))
	mut t := new_transformer(mut a, &tc, {
		'main': true
	})
	t.build_type_alias_suffix_index()
	aliases := t.type_aliases_with_short_name('Id')
	assert aliases.map(it.name) == ['foo.Id', 'Id', 'bar.Id']
	assert aliases.map(it.target_text()) == ['int', 'u64', 'shared Store']
	assert t.type_aliases_with_short_name('Missing').len == 0
	assert flat.source_type_name(t.shared_alias_storage_type(flat.source_type_id('Id'))) == '&Store'
}

fn test_type_aliases_with_short_name_rescans_a_stale_index() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	tc.type_aliases.set_id('foo.Id', flat.source_type_int)
	mut t := new_transformer(mut a, &tc, {
		'main': true
	})
	t.build_type_alias_suffix_index()
	tc.type_aliases.set_id('bar.Id', flat.source_type_u64)
	assert t.type_aliases_with_short_name('Id').map(it.name) == ['foo.Id', 'bar.Id']
}

fn test_registered_interfaces_take_precedence_over_unrelated_alias_suffixes() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	tc.interface_names['IError'] = true
	tc.interface_names['Reader'] = true
	tc.interface_names['pkg.LocalError'] = true
	tc.type_aliases.set_id('pkg.IError', flat.source_type_id('pkg.LocalError'))
	tc.type_aliases.set_id('pkg.Reader', flat.source_type_id('pkg.LocalError'))
	mut t := new_transformer(mut a, &tc, map[string]bool{})
	t.build_type_alias_suffix_index()
	for module_name in ['builtin', 'main', 'pkg', 'main'] {
		t.cur_module = module_name
		for name in ['IError', 'Reader'] {
			expected := if module_name == 'pkg' { 'pkg.LocalError' } else { name }
			for prefix in ['', '&', '!', '[]'] {
				assert flat.source_type_name(t.normalize_type_alias(flat.source_type_id(prefix + name))) == prefix + expected
			}
			for prefix in ['', '&'] {
				assert flat.source_type_name(t.resolve_interface_type_name(flat.source_type_id(prefix + name))) == expected
			}
			assert flat.source_type_name(t.normalize_type_alias(flat.source_type_id('pkg.${name}'))) == 'pkg.LocalError'
		}
	}
}
