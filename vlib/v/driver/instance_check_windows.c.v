module driver

import v.flat
import v.types

// Windows validates instances as the build specializes them. Unlike the separate
// check, this must retain library bodies for the following C generation.
fn start_program_instance_check(mut a flat.FlatAst, mut tc types.TypeChecker, is_checker_fixture bool, fatal_errors bool, message_limit int, skip_notices bool) ProgramInstanceCheck {
	tc.check_build_generic_bodies = true
	return ProgramInstanceCheck{}
}

fn (check ProgramInstanceCheck) finish() int {
	return -1
}
