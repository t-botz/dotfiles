# Working on these dotfiles

- Keep one shared configuration where behavior is portable, with explicit platform-specific settings where it is not.
- Keep bootstrap easy to run and safe to repeat.
- Bootstrap should configure the whole machine
- For significant changes, test installation and recovery in disposable environments.

## Documentation and style

- Keep README.md lean: a high-level overview and basic commands, comfortably under 100 lines. Avoid implementation details, test transcripts, and information that needs frequent edits.

## Validation

- Use the local WSL harness in tests/test-wsl.ps1 for bootstrap behavior changes; use a disposable Tart VM for macOS activation.
- Full Windows validation should start from a clean Windows VM and cover host setup, WSL provisioning, and guest configuration end to end. The WSL harness covers only the guest portion.
