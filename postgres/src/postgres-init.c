#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>

#define PG_UID 999
#define PG_GID 999
#define PG_DATA "/var/lib/postgresql/data"
#define PG_BIN "/usr/bin/postgres"
#define INITDB_BIN "/usr/bin/initdb"

// دالة مساعدة لنسخ الملفات بلغة C مباشرة (بدون الحاجة لـ cp)
int copy_file(const char *src_path, const char *dst_path, uid_t owner, gid_t group) {
    FILE *src = fopen(src_path, "rb");
    if (!src) {
        perror("Failed to open source file");
        return -1;
    }

    FILE *dst = fopen(dst_path, "wb");
    if (!dst) {
        perror("Failed to open dest file");
        fclose(src);
        return -1;
    }

    char buffer[4096];
    size_t bytes;
    while ((bytes = fread(buffer, 1, sizeof(buffer), src)) > 0) {
        fwrite(buffer, 1, bytes, dst);
    }

    fclose(src);
    fclose(dst);

    // تغيير المالك للملف الجديد
    if (chown(dst_path, owner, group) != 0) {
        perror("Failed to chown new file");
    }
    
    printf("=> Copied %s to %s\n", src_path, dst_path);
    return 0;
}

int is_initialized() {
    char path[256];
    snprintf(path, sizeof(path), "%s/PG_VERSION", PG_DATA);
    struct stat st;
    return (stat(path, &st) == 0);
}

void run_as_postgres(char *cmd, char **args) {
    pid_t pid = fork();
    if (pid == 0) {
        setgid(PG_GID);
        setuid(PG_UID);
        execv(cmd, args);
        perror("Exec failed");
        exit(1);
    } else if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
            fprintf(stderr, "Command failed: %s\n", cmd);
            exit(1);
        }
    } else {
        perror("Fork failed");
        exit(1);
    }
}

int main(int argc, char **argv) {
    // Smart Routing
    if (argc > 1 && argv[1][0] != '-' && strcmp(argv[1], "postgres") != 0) {
        setgid(PG_GID);
        setuid(PG_UID);
        execvp(argv[1], &argv[1]);
        return 1;
    }

    // SUID Check & Permissions Fix
    if (geteuid() == 0) {
        chown(PG_DATA, PG_UID, PG_GID);
        chown("/var/run/postgresql", PG_UID, PG_GID);
        chmod("/var/run/postgresql", 0775);
    }

    // Initialization Logic
    if (!is_initialized()) {
        char *init_args[] = {
            "initdb",
            "-D", PG_DATA,
            "-E", "UTF8",
            "--no-locale",
            "-A", "trust",
            NULL
        };
        
        // Run initdb as postgres user
        if (geteuid() == 0) {
            run_as_postgres(INITDB_BIN, init_args);
        } else {
             pid_t pid = fork();
             if (pid == 0) {
                 execv(INITDB_BIN, init_args);
                 exit(1);
             }
             wait(NULL);
        }
        
        copy_file("/usr/local/etc/postgres/postgresql.conf", 
                  "/var/lib/postgresql/data/postgresql.conf", 
                  PG_UID, PG_GID);
                  
        copy_file("/usr/local/etc/postgres/pg_hba.conf", 
                  "/var/lib/postgresql/data/pg_hba.conf", 
                  PG_UID, PG_GID);
    }

    // Drop Privileges
    if (geteuid() == 0) {
        if (setgid(PG_GID) != 0 || setuid(PG_UID) != 0) {
            perror("Failed to drop privileges");
            return 1;
        }
    }

    // Start Server
    char *new_argv[argc + 10];
    int idx = 0;

    new_argv[idx++] = "postgres";
    new_argv[idx++] = "-D";
    new_argv[idx++] = PG_DATA;
    new_argv[idx++] = "-c";
    new_argv[idx++] = "config_file=/var/lib/postgresql/data/postgresql.conf";
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "postgres") == 0) continue;
        new_argv[idx++] = argv[i];
    }
    new_argv[idx] = NULL;

    execv(PG_BIN, new_argv);
    perror("FATAL: Failed to exec postgres");
    return 1;
}