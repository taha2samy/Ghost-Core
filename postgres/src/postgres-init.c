#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <dirent.h>
#include <string.h>
#include <errno.h>

#define PG_UID 999
#define PG_GID 999
#define PG_DATA "/var/lib/postgresql/data"
#define PG_BIN "/usr/bin/postgres"
#define INITDB_BIN "/usr/bin/initdb"

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
    if (argc > 1 && argv[1][0] != '-') {
        execvp(argv[1], &argv[1]);
        return 1;
    }

    chown(PG_DATA, PG_UID, PG_GID);
    chown("/var/run/postgresql", PG_UID, PG_GID);
    chmod("/var/run/postgresql", 0775);

    if (!is_initialized()) {
        char *init_args[] = {
            "initdb",
            "-D", PG_DATA,
            "-E", "UTF8",
            "--no-locale",
            NULL
        };
        run_as_postgres(INITDB_BIN, init_args);
        
        system("cp /usr/local/etc/postgres/postgresql.conf /var/lib/postgresql/data/postgresql.conf");
        system("cp /usr/local/etc/postgres/pg_hba.conf /var/lib/postgresql/data/pg_hba.conf");
        
        chown("/var/lib/postgresql/data/postgresql.conf", PG_UID, PG_GID);
        chown("/var/lib/postgresql/data/pg_hba.conf", PG_UID, PG_GID);
    }

    if (setgid(PG_GID) != 0 || setuid(PG_UID) != 0) {
        perror("Failed to drop privileges");
        return 1;
    }

    char *new_argv[argc + 5];
    new_argv[0] = "postgres";
    new_argv[1] = "-D";
    new_argv[2] = PG_DATA;
    new_argv[3] = "-c";
    new_argv[4] = "config_file=/var/lib/postgresql/data/postgresql.conf";
    
    for (int i = 1; i < argc; i++) {
        new_argv[4 + i] = argv[i];
    }
    new_argv[4 + argc] = NULL;

    execv(PG_BIN, new_argv);
    perror("FATAL: Failed to exec postgres");
    return 1;
}