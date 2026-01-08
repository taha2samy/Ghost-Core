#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>

#define REDIS_UID 999
#define REDIS_GID 999

int main(int argc, char **argv) {
    uid_t current_uid = getuid();

    if (current_uid == 0) {
        printf("=> [redis-init] Running as root. Attempting system tuning...\n");

        FILE *f = fopen("/proc/sys/vm/overcommit_memory", "w");
        if (f) {
            fprintf(f, "1");
            fclose(f);
            printf("=> [redis-init] vm.overcommit_memory set to 1\n");
        } else {
            printf("=> [redis-init] Warning: Failed to write overcommit_memory (Read-only fs?)\n");
        }

        printf("=> [redis-init] Dropping privileges to redis (%d:%d)...\n", REDIS_UID, REDIS_GID);
        if (setgid(REDIS_GID) != 0) {
            perror("Failed setgid");
            return 1;
        }
        if (setuid(REDIS_UID) != 0) {
            perror("Failed setuid");
            return 1;
        }
    } else {
        printf("=> [redis-init] Running as non-root (UID: %d). Skipping system tuning.\n", current_uid);
    }

    char *redis_bin = "/usr/bin/redis-server";
    char *config_file = "/usr/local/etc/redis/redis.conf";

    if (argc > 1) {
        config_file = argv[1];
    }

    char *new_argv[] = {
        "redis-server",
        config_file,
        NULL
    };

    printf("=> [redis-init] Starting %s with config %s...\n", redis_bin, config_file);
    execv(redis_bin, new_argv);

    perror("=> [redis-init] Failed exec redis-server");
    return 1;
}
