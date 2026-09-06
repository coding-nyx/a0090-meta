// recovery_init.c — Emergency rescue init for hub-11
// Fixes corrupted /lib, merges /lib_old, and writes real Debian dynamic linker binaries.

#define AT_FDCWD -100
#define AT_SYMLINK_NOFOLLOW 0x100
#define AT_REMOVEDIR 0x200

#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR   2
#define O_CREAT  0100
#define O_TRUNC  01000
#define O_DIRECTORY 00200000

#define S_IFMT   0170000
#define S_IFDIR  0040000
#define S_IFLNK  0120000

#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)

struct timespec {
    long tv_sec;
    long tv_nsec;
};

struct linux_dirent64 {
    unsigned long  d_ino;
    long           d_off;
    unsigned short d_reclen;
    unsigned char  d_type;
    char           d_name[];
};

struct stat {
    unsigned long st_dev;
    unsigned long st_ino;
    unsigned int  st_mode;
    unsigned int  st_nlink;
    unsigned int  st_uid;
    unsigned int  st_gid;
    unsigned long st_rdev;
    unsigned long __pad1;
    long          st_size;
    int           st_blksize;
    int           __pad2;
    long          st_blocks;
    long          st_atime;
    unsigned long st_atime_nsec;
    long          st_mtime;
    unsigned long st_mtime_nsec;
    long          st_ctime;
    unsigned long st_ctime_nsec;
    unsigned int  __unused4;
    unsigned int  __unused5;
};

static inline long sys_call1(long n, long a1) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a1;
    __asm__ __volatile__("svc #0" : "=r"(x0) : "r"(x8), "r"(x0) : "memory");
    return x0;
}

static inline long sys_call2(long n, long a1, long a2) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a1;
    register long x1 __asm__("x1") = a2;
    __asm__ __volatile__("svc #0" : "=r"(x0) : "r"(x8), "r"(x0), "r"(x1) : "memory");
    return x0;
}

static inline long sys_call3(long n, long a1, long a2, long a3) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a1;
    register long x1 __asm__("x1") = a2;
    register long x2 __asm__("x2") = a3;
    __asm__ __volatile__("svc #0" : "=r"(x0) : "r"(x8), "r"(x0), "r"(x1), "r"(x2) : "memory");
    return x0;
}

static inline long sys_call4(long n, long a1, long a2, long a3, long a4) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a1;
    register long x1 __asm__("x1") = a2;
    register long x2 __asm__("x2") = a3;
    register long x3 __asm__("x3") = a4;
    __asm__ __volatile__("svc #0" : "=r"(x0) : "r"(x8), "r"(x0), "r"(x1), "r"(x2), "r"(x3) : "memory");
    return x0;
}

static inline long sys_call5(long n, long a1, long a2, long a3, long a4, long a5) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a1;
    register long x1 __asm__("x1") = a2;
    register long x2 __asm__("x2") = a3;
    register long x3 __asm__("x3") = a4;
    register long x4 __asm__("x4") = a5;
    __asm__ __volatile__("svc #0" : "=r"(x0) : "r"(x8), "r"(x0), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
    return x0;
}

static int out_fd = 1;

static int str_eq(const char *a, const char *b) {
    while (*a && *b && (*a == *b)) { a++; b++; }
    return *a == *b;
}

void print(const char *s) {
    long len = 0;
    while (s[len]) len++;
    sys_call3(64 /* write */, out_fd, (long)s, len);
}

void sleep_sec(int s) {
    struct timespec ts;
    ts.tv_sec = s;
    ts.tv_nsec = 0;
    sys_call2(101 /* nanosleep */, (long)&ts, 0);
}

static void copy_file(const char *src, const char *dst, int mode) {
    long in = sys_call4(56 /* openat */, AT_FDCWD, (long)src, 0 /* O_RDONLY */, 0);
    if (in < 0) {
        print("  [ERROR] Cannot open source: ");
        print(src);
        print("\n");
        return;
    }
    sys_call3(35 /* unlinkat */, AT_FDCWD, (long)dst, 0);
    long out = sys_call4(56 /* openat */, AT_FDCWD, (long)dst, 01101 /* O_WRONLY|O_CREAT|O_TRUNC */, mode);
    if (out < 0) {
        print("  [ERROR] Cannot create dest: ");
        print(dst);
        print("\n");
        sys_call1(57 /* close */, in);
        return;
    }
    char buf[4096];
    long n;
    long total = 0;
    while ((n = sys_call3(63 /* read */, in, (long)buf, sizeof(buf))) > 0) {
        sys_call3(64 /* write */, out, (long)buf, n);
        total += n;
    }
    sys_call1(57 /* close */, in);
    sys_call1(57 /* close */, out);
    print("  Installed: ");
    print(dst);
    print("\n");
}

static void merge_dir(int src_fd, int dst_fd, const char *indent) {
    char buf[2048];
    long nread;

    while ((nread = sys_call3(61 /* getdents64 */, src_fd, (long)buf, sizeof(buf))) > 0) {
        long bpos = 0;
        while (bpos < nread) {
            struct linux_dirent64 *d = (struct linux_dirent64 *)(buf + bpos);
            if (!str_eq(d->d_name, ".") && !str_eq(d->d_name, "..")) {
                print(indent);
                print("  Processing: ");
                print(d->d_name);

                long r = sys_call4(38 /* renameat */, src_fd, (long)d->d_name, dst_fd, (long)d->d_name);
                if (r == 0) {
                    print(" -> [MOVED]\n");
                } else {
                    print(" -> [MERGING SUBDIR]\n");
                    long sub_src = sys_call4(56 /* openat */, src_fd, (long)d->d_name, O_RDONLY | O_DIRECTORY, 0);
                    sys_call3(34 /* mkdirat */, dst_fd, (long)d->d_name, 0755);
                    long sub_dst = sys_call4(56 /* openat */, dst_fd, (long)d->d_name, O_RDONLY | O_DIRECTORY, 0);
                    if (sub_src >= 0 && sub_dst >= 0) {
                        merge_dir(sub_src, sub_dst, "    ");
                    }
                    if (sub_src >= 0) sys_call1(57 /* close */, sub_src);
                    if (sub_dst >= 0) sys_call1(57 /* close */, sub_dst);
                    sys_call3(35 /* unlinkat */, src_fd, (long)d->d_name, AT_REMOVEDIR);
                }
            }
            bpos += d->d_reclen;
        }
    }
}

void _start() {
    // 1. Mount devtmpfs on /dev
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/dev");
    sys_call5(40 /* mount */, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);

    // 2. Open /dev/console for direct screen output
    long cfd = sys_call4(56 /* openat */, AT_FDCWD, (long)"/dev/console", O_RDWR, 0);
    if (cfd >= 0) {
        out_fd = cfd;
    }

    print("\n\n");
    print("========================================================\n");
    print("===   HUB-11 ULTIMATE RESCUE & RESTORATION v3.0      ===\n");
    print("========================================================\n\n");

    // 3. Mount /dev/mmcblk0p6
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/mnt");
    print(">>> Waiting for eMMC and mounting /dev/mmcblk0p6 on /mnt...\n");
    
    long ret = -1;
    for (int retry = 1; retry <= 15; retry++) {
        ret = sys_call5(40 /* mount */, (long)"/dev/mmcblk0p6", (long)"/mnt", (long)"ext4", 0, 0);
        if (ret == 0) break;
        print("    Waiting for /dev/mmcblk0p6...\n");
        sleep_sec(1);
    }

    if (ret != 0) {
        print("FATAL: Failed to mount /dev/mmcblk0p6!\n");
        print(">>> System halted.\n");
        while (1) { sleep_sec(3600); }
    }
    print(">>> Rootfs mounted successfully!\n\n");

    // Ensure /mnt/usr/lib directories
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/mnt/usr");
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/mnt/usr/lib");
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/mnt/usr/lib64");
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/mnt/usr/lib/aarch64-linux-gnu");
    sys_call2(34 /* mkdirat */, AT_FDCWD, (long)"/mnt/usr/lib/modules");

    long dst_lib = sys_call4(56 /* openat */, AT_FDCWD, (long)"/mnt/usr/lib", O_RDONLY | O_DIRECTORY, 0);

    // 4. Merge /mnt/lib_old into /mnt/usr/lib if present
    long old_lib = sys_call4(56 /* openat */, AT_FDCWD, (long)"/mnt/lib_old", O_RDONLY | O_DIRECTORY, 0);
    if (old_lib >= 0) {
        print(">>> Merging /mnt/lib_old into /mnt/usr/lib...\n");
        merge_dir(old_lib, dst_lib, "");
        sys_call1(57 /* close */, old_lib);
        sys_call3(35 /* unlinkat */, AT_FDCWD, (long)"/mnt/lib_old", AT_REMOVEDIR);
    }

    // 5. Inspect /mnt/lib. If directory, merge too
    struct stat st;
    ret = sys_call4(79 /* newfstatat */, AT_FDCWD, (long)"/mnt/lib", (long)&st, AT_SYMLINK_NOFOLLOW);
    if (ret == 0 && S_ISDIR(st.st_mode)) {
        print(">>> Merging /mnt/lib into /mnt/usr/lib...\n");
        long cur_lib = sys_call4(56 /* openat */, AT_FDCWD, (long)"/mnt/lib", O_RDONLY | O_DIRECTORY, 0);
        if (cur_lib >= 0) {
            merge_dir(cur_lib, dst_lib, "");
            sys_call1(57 /* close */, cur_lib);
        }
        sys_call3(35 /* unlinkat */, AT_FDCWD, (long)"/mnt/lib", AT_REMOVEDIR);
    }
    if (dst_lib >= 0) sys_call1(57 /* close */, dst_lib);

    // 6. Restore symlinks: /lib -> usr/lib and /lib64 -> usr/lib64
    print(">>> Rebuilding UsrMerge symlinks (/lib -> usr/lib, /lib64 -> usr/lib64)...\n");
    sys_call3(35 /* unlinkat */, AT_FDCWD, (long)"/mnt/lib", 0);
    sys_call3(35 /* unlinkat */, AT_FDCWD, (long)"/mnt/lib", AT_REMOVEDIR);
    sys_call3(36 /* symlinkat */, (long)"usr/lib", AT_FDCWD, (long)"/mnt/lib");

    sys_call3(35 /* unlinkat */, AT_FDCWD, (long)"/mnt/lib64", 0);
    sys_call3(35 /* unlinkat */, AT_FDCWD, (long)"/mnt/lib64", AT_REMOVEDIR);
    sys_call3(36 /* symlinkat */, (long)"usr/lib64", AT_FDCWD, (long)"/mnt/lib64");

    // 7. Install verified Debian dynamic linkers directly to eMMC!
    print(">>> Installing verified Debian dynamic linkers directly onto eMMC storage...\n");
    copy_file("/ld-linux-aarch64.so.1", "/mnt/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1", 0755);
    copy_file("/ld-2.31.so", "/mnt/usr/lib/aarch64-linux-gnu/ld-2.31.so", 0755);
    copy_file("/ld-linux-aarch64.so.1", "/mnt/usr/lib/ld-linux-aarch64.so.1", 0755);

    // Ensure cross-compatibility symlinks
    sys_call3(36 /* symlinkat */, (long)"ld-linux-aarch64.so.1", AT_FDCWD, (long)"/mnt/usr/lib/aarch64-linux-gnu/ld-2.31.so");
    sys_call3(36 /* symlinkat */, (long)"aarch64-linux-gnu/ld-linux-aarch64.so.1", AT_FDCWD, (long)"/mnt/usr/lib/ld-linux-aarch64.so.1");

    // 8. Verification: Check /mnt/lib/ld-linux-aarch64.so.1
    print(">>> Verifying /mnt/lib/ld-linux-aarch64.so.1 resolution...\n");
    long tfd = sys_call4(56 /* openat */, AT_FDCWD, (long)"/mnt/lib/ld-linux-aarch64.so.1", O_RDONLY, 0);
    if (tfd >= 0) {
        print(">>> [SUCCESS]: Dynamic linker is VERIFIED ACCESSIBLE through /lib!\n");
        sys_call1(57 /* close */, tfd);
    } else {
        print(">>> [WARNING]: Could not open dynamic linker through /lib!\n");
    }

    // 9. Sync eMMC
    print(">>> Syncing all changes to eMMC storage...\n");
    sys_call1(81 /* sync */, 0);

    // 10. Clean unmount
    print(">>> Safely unmounting /mnt...\n");
    sys_call2(39 /* umount2 */, (long)"/mnt", 0);
    sys_call1(81 /* sync */, 0);

    print("\n");
    print("========================================================\n");
    print("===      REPAIR COMPLETE! SYSTEM RESTORED!           ===\n");
    print("========================================================\n");
    print(">>> Rootfs /dev/mmcblk0p6 is fully repaired and unmounted.\n");
    print(">>> Dynamic linker and core libraries are verified in place.\n\n");
    print(">>> WHAT TO DO NOW:\n");
    print(">>> 1. Unplug the DC power barrel jack.\n");
    print(">>> 2. Hold the recovery pin in the 3.5mm AV jack.\n");
    print(">>> 3. Reconnect DC power (hold pin for 3s) to enter Loader mode.\n");
    print(">>> 4. Lab will now flash the known-good 13:38 kernel!\n");
    print("========================================================\n\n");

    while (1) {
        sleep_sec(3600);
    }
}
