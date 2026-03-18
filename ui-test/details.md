# UI Zone Tester

This is a layout test extension. It declares every possible UI zone so you can verify nothing overlaps.

## Zones being tested

- **Zone 1** — two action buttons beside Uninstall: "Open Config" and "View Logs"
- **Zone 2** — two extra tabs in the tab bar: "Configure" and "Logs"
- **Zone 3** — side panel on the left of the tab content area
- **Zone 5** — status bar strip at the bottom

## What to check

- Do the action buttons fit without pushing Uninstall off-screen?
- Do extra tabs fit in the tab bar without wrapping?
- Does the side panel sit cleanly left of the content?
- Does the status bar appear at the bottom without extra spacing?

Delete this extension once layout is confirmed.