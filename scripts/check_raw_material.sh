#!/bin/bash
# Checks for raw Material widget usage that should use Prism* wrappers instead.
# Run: ./scripts/check_raw_material.sh
#
# Advisory only — exits 0 regardless of findings.

echo "Checking for raw Material usage that should use Prism* wrappers..."
echo ""

ISSUES=0

# Check for raw AppBar in feature screens (not in shared/widgets where wrappers live)
COUNT=$(grep -rn "AppBar(" lib/features/ --include="*.dart" | grep -v "PrismTopBar\|PrismGlassAppBar\|PrismPageScaffold" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw AppBar usage(s) in feature code (use PrismTopBar/PrismPageScaffold):"
  grep -rn "AppBar(" lib/features/ --include="*.dart" | grep -v "PrismTopBar\|PrismGlassAppBar\|PrismPageScaffold"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

# Check for raw Scaffold in feature screens
COUNT=$(grep -rn "Scaffold(" lib/features/ --include="*.dart" | grep -v "PrismPageScaffold\|ScaffoldMessenger" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw Scaffold usage(s) in feature code (use PrismPageScaffold):"
  grep -rn "Scaffold(" lib/features/ --include="*.dart" | grep -v "PrismPageScaffold\|ScaffoldMessenger"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

# Check for raw ListTile in feature screens
COUNT=$(grep -rn "ListTile(" lib/features/ --include="*.dart" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw ListTile usage(s) in feature code (use PrismListRow/PrismSettingsRow):"
  grep -rn "ListTile(" lib/features/ --include="*.dart"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

# Check for raw showModalBottomSheet in feature code
COUNT=$(grep -rn "showModalBottomSheet(" lib/features/ --include="*.dart" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw showModalBottomSheet usage(s) in feature code (use PrismSheet.show):"
  grep -rn "showModalBottomSheet(" lib/features/ --include="*.dart"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

# Check for raw showDialog in feature code (but not PrismDialog internals)
COUNT=$(grep -rn "showDialog(" lib/features/ --include="*.dart" | grep -v "PrismDialog" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw showDialog usage(s) in feature code (use PrismDialog.show/confirm):"
  grep -rn "showDialog(" lib/features/ --include="*.dart" | grep -v "PrismDialog"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

# Check for raw ElevatedButton / TextButton in feature code
COUNT=$(grep -rn "ElevatedButton(\|TextButton(" lib/features/ --include="*.dart" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw ElevatedButton/TextButton usage(s) in feature code (use PrismButton):"
  grep -rn "ElevatedButton(\|TextButton(" lib/features/ --include="*.dart"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

# Check for raw context.go with string literals (should use route constants)
COUNT=$(grep -rn "context\.go('/" lib/features/ --include="*.dart" | wc -l | tr -d ' ')
if [ "$COUNT" -gt "0" ]; then
  echo "⚠ Found $COUNT raw context.go('/...') call(s) (use AppRoutePaths constants):"
  grep -rn "context\.go('/" lib/features/ --include="*.dart"
  echo ""
  ISSUES=$((ISSUES + COUNT))
fi

if [ "$ISSUES" -eq "0" ]; then
  echo "✓ No raw Material issues found."
else
  echo "Found $ISSUES potential issue(s). Not all are necessarily wrong — review context."
fi

exit 0
