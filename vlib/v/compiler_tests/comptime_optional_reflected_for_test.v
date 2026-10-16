struct OptionalReflectedRows {
	values ?[]int
}

fn optional_reflected_sum(rows OptionalReflectedRows) int {
	mut total := 0
	$for field in OptionalReflectedRows.fields {
		for value in rows.$(field.name) or { [4, 5] } {
			total += value
		}
	}
	return total
}

fn test_optional_reflected_for_uses_fallback_payload_type() {
	assert optional_reflected_sum(OptionalReflectedRows{}) == 9
}

fn test_optional_reflected_for_uses_present_payload() {
	assert optional_reflected_sum(OptionalReflectedRows{ values: [7, 8] }) == 15
}

fn optional_reflected_weighted_sum(rows OptionalReflectedRows) int {
	mut total := 0
	$for field in OptionalReflectedRows.fields {
		for index, value in (rows.$(field.name) or { [4, 5] }) {
			total += (index + 1) * value
		}
	}
	return total
}

fn test_optional_reflected_for_types_index_and_value() {
	assert optional_reflected_weighted_sum(OptionalReflectedRows{}) == 14
	assert optional_reflected_weighted_sum(OptionalReflectedRows{ values: [7, 8] }) == 23
}

fn test_optional_reflected_for_without_fallback_types_payload() {
	rows := OptionalReflectedRows{ values: [7, 8] }
	mut total := 0
	$for field in OptionalReflectedRows.fields {
		for value in rows.$(field.name) {
			total += value
		}
	}
	assert total == 15
}
