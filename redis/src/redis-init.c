

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>

#define REDIS_UID 999
#define REDIS_GID 999

int main(int argc, char **argv) {
    // 1. Fix Kernel Settings
    printf("=> [redis-init] Checking vm.overcommit_memory...\n");
    FILE *f = fopen("/proc/sys/vm/overcommit_memory", "w");
    if (f) {
        if (fprintf(f, "1") > 0) {
            printf("=> [redis-init] SUCCESS: vm.overcommit_memory set to 1.\n");
        } else {
            fprintf(stderr, "=> [redis-init] WARNING: Failed to write to /proc/sys/vm/overcommit_memory.\n");
        }
        fclose(f);
    } else {
        fprintf(stderr, "=> [redis-init] WARNING: Cannot open /proc/sys/vm/overcommit_memory (Permission Denied).\n");
    }

    // 2. Drop Privileges
    printf("=> [redis-init] Dropping privileges to user redis (%d:%d)...\n", REDIS_UID, REDIS_GID);
    if (setgid(REDIS_GID) != 0) {
        perror("=> [redis-init] FATAL: Failed to set GID");
        return 1;
    }
    if (setuid(REDIS_UID) != 0) {
        perror("=> [redis-init] FATAL: Failed to set UID");
        return 1;
    }

    // 3. Launch Redis Server directly
    printf("=> [redis-init] Starting redis-server as unprivileged user...\n");
    
    char *redis_bin = "/usr/bin/redis-server";
    argv[0] = "redis-server";

    execv(redis_bin, argv);

    perror("=> [redis-init] FATAL: Failed to exec redis-server");
    return 1;
}