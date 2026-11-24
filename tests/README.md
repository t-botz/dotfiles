# Local validation

Install Oracle VirtualBox on Windows Home; no Extension Pack is needed. The Windows guest does not need nested
virtualization: Windows app setup and Linux configuration are tested separately.

1. Download an official [Windows 11 evaluation ISO](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise) from Microsoft.
2. Run `new-windows-vm.ps1 -IsoPath <path>` once to create the clean baseline.
3. Run `test-windows.ps1` for each Windows setup change.
4. Run `test-wsl.ps1` for each Linux bootstrap change.
5. Run `test-windows-installer.ps1` for Windows download-entry changes.

Use the same `-WorkDir <path>` for the two Windows VM commands if overriding
its default. Run the Windows and WSL suites sequentially, with at least 45 GiB free before each run. Tests stop their own guest if free space falls below 10 GiB. The baseline, ISO and caches are retained between runs. The Windows
evaluation expires; recreate the baseline using a current evaluation when needed.

Each Windows run creates a linked clone of the clean snapshot, with NAT networking,
no shared host directories, and clipboard and drag-and-drop disabled. Its random
local-account password stays in the test work directory. Automatic administrator
consent is enabled only in this test guest, to let app installers run unattended.
The tests cover installation, configuration backups, repeated setup and restart.

Each WSL run imports a separate Ubuntu distribution with Windows drive mounting
and Windows interoperability disabled. It tests fresh bootstrap, all configured
mise tools, shell startup, backups, recovery, preserved local edits and restart.
Compilation is limited to two jobs to suit a laptop.

Successful guests are deleted. Failed guests are retained with logs for inspection;
`-Keep` also retains successful guests. The baseline and download caches are kept.
Never reuse a personal VM or WSL distribution as a test fixture.

Finally, run `bootstrap.ps1` on the real Windows host and repeat it. This validates
Windows-to-WSL integration against the existing machine. It can change the host,
and it does not validate clean Windows feature provisioning or its reboot path.
Normal host administrator prompts and Linux account password setup are interactive.
macOS activation requires its separate disposable Tart validation.

The installer-entry test uses Windows PowerShell 5.1, an already installed Git,
a disposable local repository with a small bootstrap fixture, and paths containing
spaces. It checks clone/dispatch, returned bootstrap statuses, local edits, unrelated directories and recovery.
It does not run the machine bootstrap; the VM and real-host runs cover that.

The Windows bootstrap applies the current checkout through its WSL path, so local
edits are included. Linux build output lives in the Linux cache directory to avoid
creating Linux symlinks in the Windows checkout.
