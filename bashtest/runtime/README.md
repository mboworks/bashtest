# Managed Windows runtime

Bashtest's Windows x86-64 launcher resolves a pinned MSYS2 Bash executable through
Bazel runfiles. The native launcher prepends its directory to the process PATH,
so both framework utilities and child processes find the bundled programs.
All executables and DLLs in `usr/bin` are declared runtime inputs, including for
manifest-only execution. Linux and macOS keep using the installed shell tools.

The repository rule downloads the official MSYS2 base archive dated 2026-09-27
and diffutils 3.12-1, verifying their SHA-256 hashes. The base includes Bash,
coreutils, grep with PCRE, sed, and runtime libraries; diffutils is an additional
package. No package manager is run, and no system installation is modified.
Only targets needing the Windows runtime fetch these archives. Expect roughly
42 MB of compressed downloads plus extracted files and the Bazel cache.

Sources and package metadata:

- [MSYS2 distribution archives](https://repo.msys2.org/distrib/x86_64/)
- [MSYS2 package archives](https://repo.msys2.org/msys/x86_64/)
- [MSYS2 package sources](https://github.com/msys2/MSYS2-packages)

Upstream binaries retain their own licenses, including GPL licenses; bashtest's
Apache-2.0 license does not relicense them. The downloaded archive keeps upstream
license and package metadata, and license files are included in runtime inputs.
Update the archive URLs and hashes together, then run the clean-environment
Windows CI test, including the PCRE and golden-file checks.

The launcher uses Bazel's native Windows launcher and launcher-maker targets,
matching rules_shell's approach. It neither registers a global shell toolchain
nor changes unrelated `sh_test` or `genrule` behavior. Native Windows ARM64 is not
provided. Remote Windows execution has not been validated; declaring the runtime
inputs alone is not a claim of remote-execution support. MSYS2 runtime relocation,
worker filesystem policies, and launcher availability also need validation.
