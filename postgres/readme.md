

# Ghost Core PostgreSQL

A highly opinionated, hardened, and architectural reconstruction of the PostgreSQL container image. This project is not merely a repackaging of upstream binaries; it is a **purpose-built database appliance** designed to meet the strictest security requirements of **Ghost Core**.

Unlike standard images (Debian/Alpine) or generic distroless variants, this image is built entirely from source code to ensure absolute control over compile-time flags, dependencies, and runtime behavior. It bridges the gap between **Extreme Security** (Distroless/Static) and **Operational Reality** (initdb, backups, and volume permissions).

### 🛡️ Why this image exists?

Standard PostgreSQL Docker images often suffer from "Bloatware" (unused system tools), excessive privileges (running as root), or reliance on heavy package managers (`apt`, `apk`) that increase the attack surface.

**Ghost Core PostgreSQL** solves these challenges through a rigorous engineering approach:

1.  **True Distroless Runtime:** The final image contains **no package manager**, no network utilities (like `curl`, `wget`, `nc`), and no compilers. It contains *only* the PostgreSQL binaries and the specific system libraries required to boot the kernel.
2.  **Built from Source:** We do not install pre-packaged binaries. We compile PostgreSQL `v17.7` directly from source code within a secure Wolfi environment. This allows us to strip unnecessary extensions (e.g., `perl`, `python`, `tcl`) at the binary level.
3.  **Advanced Process Orchestration:** Instead of a fragile 300-line Bash script, we utilize a compiled **Custom C Entrypoint (`postgres-init`)**. This binary acts as a PID 1 supervisor, handling the complex logic of volume permissions, database initialization (`initdb`), and privilege de-escalation with kernel-level precision.
4.  **Zero-Trust Identity:** The container is configured to run as `USER 999` (postgres) by default in the Dockerfile, enforcing the **Principle of Least Privilege** out of the box, while solving the "Permission Denied" volume issues via a specialized **SUID** strategy.

This is a production-grade image designed for environments where security compliance and minimal footprint are non-negotiable.



## 🧠 Architecture: The Custom C Entrypoint (`postgres-init.c`)

Standard container images typically rely on complex, heavy Bash scripts (`docker-entrypoint.sh`) to handle initialization logic. While flexible, these scripts introduce security risks (shell injection) and dependency bloat.

In **Ghost Core**, we replaced the shell script with a compiled **C binary** (`/usr/bin/postgres-init`). This binary acts as the **PID 1 Orchestrator**, managing the entire lifecycle of the container from startup to handover.

> **![Place for Image: architecture-flow.png]**
> *Figure 1: The SUID execution flow and privilege transition.*

### 1. The Orchestrator Role
The `postgres-init` binary is not the database itself; it is a supervisor. Its primary responsibility is to prepare the filesystem state before the PostgreSQL server starts. It performs the following critical logic using native **Linux System Calls**:

1.  **State Inspection:** It checks `/var/lib/postgresql/data` for the existence of `PG_VERSION` to determine if this is a fresh install or a restart.
2.  **Configuration Injection:** Instead of relying on external `cp` commands (which might fail in a Distroless env), it implements internal C functions to copy our hardened `postgresql.conf` and `pg_hba.conf` to the data directory.
3.  **Process Handover:** It uses `execv()` to replace itself in memory with the actual `postgres` binary, ensuring the database server inherits PID 1 (crucial for signal handling like `SIGTERM`).

### 2. The SUID Strategy (`chmod u+s`)
This is the most critical architectural decision in this image. It solves the "Docker Volume Permission" paradox.

#### The Paradox:
*   For security, we want the container to run as `USER 999` (non-root) by default.
*   However, when Docker mounts a volume to `/var/lib/postgresql/data`, it is often owned by `root` on the host.
*   A process running as `USER 999` cannot write to a root-owned volume, causing the container to crash immediately.

#### The Solution:
We utilize the **SUID (Set User ID)** permission bit on the entrypoint binary.

*   **In Dockerfile:** We set `USER 999` (Final Stage) and run `chmod u+s /usr/bin/postgres-init` (Builder Stage).
*   **At Runtime:**
    1.  Docker starts the process as `UID 999`.
    2.  The Linux Kernel detects the SUID bit on the file.
    3.  The Kernel elevates the **Effective UID (EUID)** of the running process to `0` (Root), while the Real UID remains `999`.
    4.  The C code detects this elevation (`geteuid() == 0`) and performs the necessary `chown` operations to fix volume permissions.

### 3. Privilege Drop Lifecycle (Root → User 999)
Security is meaningless if the process remains Root. Our C entrypoint implements a strict **Privilege Drop** mechanism to ensure the final database process is unprivileged.

The code follows this strict sequence:

1.  **Elevated Phase (Effective Root):**
    *   Fix ownership of `/var/lib/postgresql/data`.
    *   Fix ownership of `/var/run/postgresql`.
    *   Execute `initdb` (if needed) to bootstrap the database cluster.
    *   Copy configuration files to the writable data directory.

2.  **The Drop (Irreversible):**
    Before executing the database server, the code makes the following system calls:
    ```c
    setgid(999); // Drop Group Privileges
    setuid(999); // Drop User Privileges
    ```
    This action permanently discards the Root powers obtained via SUID.

3.  **Execution Phase (Unprivileged):**
    The `postgres` binary is launched. At this point, the process is strictly running as `postgres:postgres` with no way to regain Root access, protecting the host in case of a SQL-injection compromise.



## 🐳 Dockerfile Engineering Decisions

Building a truly Distroless image for a complex system like PostgreSQL requires solving several low-level system dependencies that automated tools often miss.

### 1. The Shell Dilemma: Why `/bin/sh` & `cp` Remain
A core tenet of Distroless is the removal of the shell. However, PostgreSQL is fundamentally designed as an **Ecosystem**, not a standalone binary.

> **![Place for Image: dependency-graph.png]**
> *Figure 2: The internal dependency graph showing why PostgreSQL components require a shell.*

We attempted to remove the shell entirely, but this broke core functionality:
*   **`initdb` Failure:** During bootstrapping, `initdb` uses C functions (`system()`, `popen()`) to invoke other executables (like `postgres -V`) to check version compatibility. The Linux kernel and glibc implement `system()` by hardcoding a call to `/bin/sh -c`. Without a shell, initialization crashes.
*   **`pg_ctl` Failure:** The control utility for restarting/reloading the server relies on shell signaling.
*   **Archiving & Backups:** Production PostgreSQL setups use `archive_command` to push WAL logs to external storage. This command is executed via a shell. Removing the shell would render the database incapable of Point-in-Time Recovery (PITR).

**The Decision:**
We retain a **minimal `bash` binary** (symlinked as `/bin/sh`) and the `cp` utility.
*   **Security Context:** This is an *infrastructure dependency*, not a user tool. We removed all network downloaders (`curl`, `wget`, `nc`) and package managers (`apk`, `apt`), leaving an attacker with a shell but no tools to download malware or move laterally.

### 2. Manual Library Extraction (NSS, ICU, & Terminal Libs)
The `extract_libs.sh` script (which relies on `ldd`) is excellent for detecting direct dependencies, but it fails to capture **Dynamic Plugins** loaded at runtime via `dlopen()`.

We encountered and solved three critical runtime failures:

#### A. The "User Not Found" Error (NSS)
*   **Symptom:** `initdb: user 'postgres' does not exist`, despite `/etc/passwd` being present.
*   **Root Cause:** Linux user resolution (UID to Name) relies on the **Name Service Switch (NSS)**. Glibc loads `libnss_files.so` dynamically at runtime to read `/etc/passwd`. Since `ldd` doesn't see this plugin, it wasn't copied.
*   **Fix:** We manually copy `libnss_files.so`, `libnss_dns.so` (for DNS resolution), and inject a valid `/etc/nsswitch.conf` file.

#### B. The "Collator Error" (ICU)
*   **Symptom:** `FATAL: could not open collator for locale`.
*   **Root Cause:** PostgreSQL relies on **ICU (International Components for Unicode)** for text sorting. ICU requires `.dat` data files (not shared libraries) located in `/usr/share/icu`. `extract_libs.sh` ignores data directories.
*   **Fix:** We manually copy the entire `/usr/share/icu` directory from the Wolfi builder to the final image.

#### C. The "Terminal Info" Error
*   **Symptom:** `bash: error while loading shared libraries: libtinfo.so`.
*   **Root Cause:** Interactive shells depend on `ncurses` and `readline` libraries to handle terminal capabilities (colors, cursor movement).
*   **Fix:** We explicitly copy `libtinfo`, `libreadline`, and `libncurses` to ensure the minimal shell remains functional for the database's internal use.