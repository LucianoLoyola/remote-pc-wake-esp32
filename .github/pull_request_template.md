## What does this change?

<!-- A short description, and the issue it fixes, if any (e.g. "Fixes #12"). -->

## How did you test it?

<!-- What you ran and what happened. For firmware or setup changes, say on which hardware. -->

- ESP32 board:
- PC (Windows version, motherboard):
- Router:

## Checklist

- [ ] `tests/Invoke-ScriptAnalysis.ps1` passes (if PowerShell scripts changed).
- [ ] The firmware compiles (if the firmware changed).
- [ ] Scripts that change the PC: `.NOTES` help, [scripts reference](https://github.com/LucianoLoyola/remote-pc-wake-esp32/blob/main/docs/scripts-reference.md) and the runbook's Automatic/Manual options are updated.
- [ ] New `config.h` settings have a default in `remote-pc-wake.ino` and are documented in `config.example.h` and Runbook 03.
- [ ] Documentation is updated, in English, without emojis.
- [ ] No secrets (passwords, tokens, `config.h`) are included.
