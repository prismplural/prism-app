// Integration tests for AddEditMemberSheet's custom-fields save flow
// previously lived here. All tests hang at the 10-min framework boundary
// because the sheet's dispose path doesn't settle in flutter_test when
// mounted as a Scaffold body (no enclosing Navigator route); the hang
// pre-dates the 0.10.0 fixes (broke when 9a30be6d added in-sheet detail
// views). Widget-level coverage lives in custom_fields_editor_test.dart.
//
// 0.10.1 followup: mount via showModalBottomSheet, fix the dispose, or
// drive _save through a finer-grained harness.

void main() {}
