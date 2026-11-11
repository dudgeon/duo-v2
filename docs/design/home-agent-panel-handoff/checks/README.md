# Comparison images from the DL-336 build

- `list-1440-build.png`, `list-1280-build.png`: `scripts/check-ui.sh` captures (dark, as the app drew them) beside board C1 (`../screens/png/c1-allprojects@2x.png`). Measured: no left pane; the middle starts at x=0; the Needs you column is 340 wide; the Home card is an ordinary `NeedsYouCard` (`★ home` beside the title, "Open Home").
- `f648-launch-build.png`: a fresh Home folder at launch, stub `claude`: no Home session started, no "Session …" row, no sidebar button.
- `c2-homepage-build.png`: Home's page in a fixture state (`scripts/check-windows.sh home-light`): sessions in the sidebar, console at full width, like any project's (the console is blank: fixture mode has no terminal).
