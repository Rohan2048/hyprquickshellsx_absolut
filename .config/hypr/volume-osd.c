/* volume-osd.c — responsive coalesced volume/mute OSD dispatcher (C port)
 *
 * Client:
 *   volume-osd up
 *   volume-osd down
 *   volume-osd mute
 *   volume-osd micmute
 *
 * Daemon:
 *   volume-osd --daemon
 *
 * Tuning (same names as the bash version, plus new OSD throttle):
 *   VOLUME_OSD_RATE_MS          minimum ms between volume updates. Default: 45
 *   VOLUME_OSD_MUTE_MS          mute debounce window. Default: 50
 *   VOLUME_OSD_STEP             percent per event. Default: 5
 *   VOLUME_OSD_LIMIT            wpctl limit. Default: 1.25
 *   VOLUME_OSD_CACHE_TTL_MS     cache freshness. Default: 1000
 *   VOLUME_OSD_DISABLE_QS=1     test without qs OSD calls
 *   VOLUME_OSD_SHOW_UNCHANGED=1 show OSD even when clamped/no-op
 *   VOLUME_OSD_MIN_INTERVAL_MS  min ms between qs OSD calls when the pill's
 *                               10-segment bucket hasn't changed. A bucket
 *                               change always fires immediately regardless
 *                               of this interval. Default: 120
 *
 * Build:
 *   gcc -O2 -Wall -o volume-osd volume-osd.c
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <ctype.h>
#include <signal.h>
#include <time.h>
#include <poll.h>
#include <libgen.h>
#include <limits.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/wait.h>

extern char **environ;

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static const char *SINK   = "@DEFAULT_AUDIO_SINK@";
static const char *SOURCE = "@DEFAULT_AUDIO_SOURCE@";

static char g_pipepath[PATH_MAX];
static char g_lockpath[PATH_MAX];
static int  pipefd = -1;

static int  step;
static long rate_ms, mute_ms, cache_ttl_ms;
static char limit_str[32];
static int  limit_percent = 0;
static int  show_unchanged = 0;
static int  have_qs = 0;

static int  cached_percent = -1;
static long last_volume_ms = 0;

/* OSD spawn throttle state. */
static int  osd_min_interval_ms;
static int  last_osd_percent = -1;
static long last_osd_ms = 0;

/* ---------------------------------------------------------------- time */

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* ------------------------------------------------------------ env util */

static long getenv_num(const char *name, long def) {
    const char *v = getenv(name);
    if (!v || !*v) return def;
    for (const char *c = v; *c; c++) {
        if (!isdigit((unsigned char)*c)) return def;
    }
    return atol(v);
}

/* --------------------------------------------------------- percent fmt */

/* Convert "0.52", "1.00", "1.25" -> integer percent (52, 100, 125). */
static int to_percent(const char *v) {
    char buf[32];
    snprintf(buf, sizeof buf, "%s", v);

    char *dot = strpbrk(buf, ".,");
    long intpart, fracpart;

    if (dot) {
        *dot = 0;
        intpart = buf[0] ? atol(buf) : 0;
        char fracbuf[3] = "00";
        const char *fp = dot + 1;
        if (fp[0]) fracbuf[0] = fp[0];
        if (fp[0] && fp[1]) fracbuf[1] = fp[1];
        fracpart = atol(fracbuf);
    } else {
        intpart = buf[0] ? atol(buf) : 0;
        fracpart = 0;
    }
    return (int)(intpart * 100 + fracpart);
}

/* Map an absolute percent to one of 10 threshold buckets (0-10), matching
 * the QML pill's Math.round(pillValue * segments) logic. */
static int percent_bucket(int p) {
    if (limit_percent <= 0) return 0;
    return (p * 10 + limit_percent / 2) / limit_percent;
}

/* ------------------------------------------------------- process spawn */

/* Run argv, discard output, return 1 on success (exit 0), 0 otherwise.
 * Uses posix_spawn (vfork-based on glibc/Linux) instead of fork+exec to
 * avoid duplicating the parent's page tables — much cheaper on weak/low-RAM
 * hardware than a plain fork(). */
static int run_cmd(char *const argv[]) {
    pid_t pid;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    int rc = posix_spawnp(&pid, argv[0], &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    if (rc != 0) return 0;

    int status;
    if (waitpid(pid, &status, 0) < 0) return 0;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

/* Run argv, capture stdout into out (NUL-terminated). Returns bytes read or -1. */
static int run_capture(char *const argv[], char *out, size_t outsz) {
    int fds[2];
    if (pipe(fds) == -1) return -1;

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&fa, fds[0]);
    posix_spawn_file_actions_addclose(&fa, fds[1]);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    pid_t pid;
    int rc = posix_spawnp(&pid, argv[0], &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(fds[1]);
    if (rc != 0) { close(fds[0]); return -1; }

    size_t total = 0;
    ssize_t n;
    while (total < outsz - 1 && (n = read(fds[0], out + total, outsz - 1 - total)) > 0)
        total += n;
    out[total] = 0;
    close(fds[0]);

    int status;
    waitpid(pid, &status, 0);
    if (total == 0) return -1;
    return (int)total;
}

/* -------------------------------------------------------------- qs osd */

static void detect_qs(void) {
    const char *disable = getenv("VOLUME_OSD_DISABLE_QS");
    if (disable && (!strcmp(disable, "1") || !strcasecmp(disable, "true") || !strcasecmp(disable, "yes"))) {
        have_qs = 0;
        return;
    }
    const char *path = getenv("PATH");
    if (!path) { have_qs = 0; return; }

    char buf[4096];
    snprintf(buf, sizeof buf, "%s", path);
    char *saveptr = NULL;
    char *dir = strtok_r(buf, ":", &saveptr);
    while (dir) {
        char full[PATH_MAX];
        snprintf(full, sizeof full, "%s/qs", dir);
        if (access(full, X_OK) == 0) { have_qs = 1; return; }
        dir = strtok_r(NULL, ":", &saveptr);
    }
    have_qs = 0;
}

static void qs_osd(const char *a, const char *b) {
    if (!have_qs) return;
    char *argv[7];
    int i = 0;
    argv[i++] = (char *)"qs";
    argv[i++] = (char *)"msg";
    argv[i++] = (char *)"osd";
    argv[i++] = (char *)"show";
    argv[i++] = (char *)a;
    if (b) argv[i++] = (char *)b;
    argv[i] = NULL;
    run_cmd(argv);
}

/* -------------------------------------------------------- sink/source */

static int get_sink_percent(void) {
    char buf[256];
    char *argv[] = { (char *)"wpctl", (char *)"get-volume", (char *)SINK, NULL };
    int n = run_capture(argv, buf, sizeof buf);
    if (n <= 0) return -1;
    char volstr[32];
    if (sscanf(buf, "Volume: %31s", volstr) != 1) return -1;
    return to_percent(volstr);
}

static void show_sink_percent(int p) {
    char vol[16];
    snprintf(vol, sizeof vol, "%d.%02d", p / 100, p % 100);
    qs_osd("volume", vol);
}

static void show_sink_mute_state(void) {
    char buf[256];
    char *argv[] = { (char *)"wpctl", (char *)"get-volume", (char *)SINK, NULL };
    int n = run_capture(argv, buf, sizeof buf);
    if (n <= 0) return;

    if (strstr(buf, "MUTED")) qs_osd("volume_muted", "");
    else qs_osd("volume_unmuted", "");

    char volstr[32];
    if (sscanf(buf, "Volume: %31s", volstr) == 1) {
        cached_percent = to_percent(volstr);
        last_volume_ms = now_ms();
    }
}

static void show_mic_mute_state(void) {
    char buf[256];
    char *argv[] = { (char *)"wpctl", (char *)"get-volume", (char *)SOURCE, NULL };
    int n = run_capture(argv, buf, sizeof buf);
    if (n <= 0) return;
    if (strstr(buf, "MUTED")) qs_osd("mic_off", "");
    else qs_osd("mic_on", "");
}

static void change_sink_volume(int delta) {
    if (delta == 0) return;

    long now = now_ms();
    if (cached_percent < 0 || cache_ttl_ms <= 0 || (now - last_volume_ms) > cache_ttl_ms) {
        int p = get_sink_percent();
        if (p >= 0) cached_percent = p;
        else if (cached_percent < 0) return;
        last_volume_ms = now;
    }

    int percent = cached_percent;
    int newv = percent + delta;
    if (newv < 0) newv = 0;
    if (newv > limit_percent) newv = limit_percent;

    if (newv == percent) {
        last_volume_ms = now;
        if (show_unchanged) show_sink_percent(newv);
        return;
    }

    char pctarg[16];
    snprintf(pctarg, sizeof pctarg, "%d%%", newv);
    char *argv[] = { (char *)"wpctl", (char *)"set-volume", (char *)"-l",
        limit_str, (char *)SINK, pctarg, NULL };

        if (run_cmd(argv)) {
            cached_percent = newv;
            last_volume_ms = now_ms();

            /* Only spawn qs when the visible pill bucket actually changes, or
             * when osd_min_interval_ms has elapsed since the last OSD call.
             * This is what keeps a held key from spawning a Qt process on
             * every tick when most ticks don't move the pill at all. */
            long now2 = now_ms();
            int bucket_changed = (last_osd_percent < 0) ||
            (percent_bucket(newv) != percent_bucket(last_osd_percent));

            if (bucket_changed || (now2 - last_osd_ms) >= osd_min_interval_ms) {
                show_sink_percent(newv);
                last_osd_percent = newv;
                last_osd_ms = now2;
            }
        }
}

/* --------------------------------------------------------- line reader */

static char rbuf[4096];
static size_t rlen = 0, rpos = 0;

/* Returns 1 on success (line in out, no newline), 0 on timeout, -1 on error/EOF. */
static int read_line_timeout(char *out, size_t outsz, int timeout_ms) {
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (;;) {
        for (size_t i = rpos; i < rlen; i++) {
            if (rbuf[i] == '\n') {
                size_t len = i - rpos;
                if (len >= outsz) len = outsz - 1;
                memcpy(out, rbuf + rpos, len);
                out[len] = 0;
                rpos = i + 1;
                return 1;
            }
        }

        if (rpos > 0) {
            memmove(rbuf, rbuf + rpos, rlen - rpos);
            rlen -= rpos;
            rpos = 0;
        }
        if (rlen == sizeof(rbuf)) rlen = 0; /* malformed input; drop */

            int remaining_ms;
        if (timeout_ms < 0) {
            remaining_ms = -1;
        } else {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            long elapsed_ms = (now.tv_sec - start.tv_sec) * 1000
            + (now.tv_nsec - start.tv_nsec) / 1000000;
            remaining_ms = timeout_ms - (int)elapsed_ms;
            if (remaining_ms <= 0) return 0;
        }

        struct pollfd pfd = { pipefd, POLLIN, 0 };
        int pr = poll(&pfd, 1, remaining_ms);
        if (pr == 0) return 0;
        if (pr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }

        ssize_t n = read(pipefd, rbuf + rlen, sizeof(rbuf) - rlen);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            return -1;
        }
        rlen += (size_t)n;
    }
}

/* ------------------------------------------------------------- daemon */

static void on_signal(int sig) {
    (void)sig;
    unlink(g_pipepath);
    unlink(g_lockpath);
    _exit(0);
}

static void mkdir_p(char *path) {
    for (char *p = path + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(path, 0755);
            *p = '/';
        }
    }
    mkdir(path, 0755);
}

static void run_daemon(void) {
    char dircopy[PATH_MAX];
    snprintf(dircopy, sizeof dircopy, "%s", g_pipepath);
    char *dir = dirname(dircopy);
    mkdir_p(dir);

    snprintf(g_lockpath, sizeof g_lockpath, "%.4090s.lock", g_pipepath);
    int lockfd = open(g_lockpath, O_CREAT | O_RDWR, 0600);
    if (lockfd < 0) exit(1);
    if (flock(lockfd, LOCK_EX | LOCK_NB) != 0) exit(0); /* another daemon running */

        unlink(g_pipepath);
    if (mkfifo(g_pipepath, 0600) != 0) exit(1);
    chmod(g_pipepath, 0600);

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    pipefd = open(g_pipepath, O_RDWR);
    if (pipefd < 0) { unlink(g_pipepath); unlink(g_lockpath); exit(1); }

    limit_percent = to_percent(limit_str);

    int p = get_sink_percent();
    if (p >= 0) { cached_percent = p; last_volume_ms = now_ms(); }

    detect_qs();

    char pending_cmd[32] = "";

    long next_apply_ms = 0;

    for (;;) {
        char cmd[32];

        if (pending_cmd[0]) {
            snprintf(cmd, sizeof cmd, "%s", pending_cmd);
            pending_cmd[0] = 0;
        } else {
            int r = read_line_timeout(cmd, sizeof cmd, -1);
            if (r <= 0) break;
        }

        if (!strcmp(cmd, "up") || !strcmp(cmd, "down")) {
            int d = !strcmp(cmd, "up") ? step : -step;
            long now = now_ms();

            if (now >= next_apply_ms) {
                change_sink_volume(d);
                next_apply_ms = now_ms() + rate_ms;
            } else {
                int pending_delta = d;
                for (;;) {
                    now = now_ms();
                    long rem = next_apply_ms - now;
                    if (rem <= 0) break;

                    char next[32];
                    int rr = read_line_timeout(next, sizeof next, (int)rem);
                    if (rr == 1) {
                        if (!strcmp(next, "up")) pending_delta += step;
                        else if (!strcmp(next, "down")) pending_delta -= step;
                        else { snprintf(pending_cmd, sizeof pending_cmd, "%s", next); break; }
                    } else break;
                }
                if (pending_delta != 0) {
                    change_sink_volume(pending_delta);
                    next_apply_ms = now_ms() + rate_ms;
                }
            }
        } else if (!strcmp(cmd, "mute") || !strcmp(cmd, "micmute")) {
            int count = 1;
            long deadline = now_ms() + mute_ms;

            for (;;) {
                long now = now_ms();
                long rem = deadline - now;
                if (rem <= 0) break;

                char next[32];
                int rr = read_line_timeout(next, sizeof next, (int)rem);
                if (rr == 1) {
                    if (!strcmp(next, cmd)) count++;
                    else { snprintf(pending_cmd, sizeof pending_cmd, "%s", next); break; }
                } else break;
            }

            if (count % 2 == 1) {
                if (!strcmp(cmd, "mute")) {
                    char *argv[] = { (char *)"wpctl", (char *)"set-mute", (char *)SINK, (char *)"toggle", NULL };
                    run_cmd(argv);
                    show_sink_mute_state();
                } else {
                    char *argv[] = { (char *)"wpctl", (char *)"set-mute", (char *)SOURCE, (char *)"toggle", NULL };
                    run_cmd(argv);
                    show_mic_mute_state();
                }
            }
        }
        /* unknown commands: ignored */
    }

    unlink(g_pipepath);
    unlink(g_lockpath);
}

/* --------------------------------------------------------------- main */

int main(int argc, char **argv) {
    const char *envpipe = getenv("VOLUME_OSD_PIPE");
    if (envpipe && *envpipe) {
        snprintf(g_pipepath, sizeof g_pipepath, "%s", envpipe);
    } else {
        const char *rt = getenv("XDG_RUNTIME_DIR");
        if (!rt || !*rt) rt = "/tmp";
        snprintf(g_pipepath, sizeof g_pipepath, "%s/volume-osd.pipe", rt);
    }

    step = (int)getenv_num("VOLUME_OSD_STEP", 5);
    rate_ms = getenv_num("VOLUME_OSD_RATE_MS", 45);
    mute_ms = getenv_num("VOLUME_OSD_MUTE_MS", 50);
    cache_ttl_ms = getenv_num("VOLUME_OSD_CACHE_TTL_MS", 1000);
    osd_min_interval_ms = (int)getenv_num("VOLUME_OSD_MIN_INTERVAL_MS", 120);

    const char *lim = getenv("VOLUME_OSD_LIMIT");
    snprintf(limit_str, sizeof limit_str, "%s", (lim && *lim) ? lim : "1.25");

    const char *su = getenv("VOLUME_OSD_SHOW_UNCHANGED");
    show_unchanged = su && (!strcmp(su, "1") || !strcasecmp(su, "true"));

    if (argc < 2) {
        fprintf(stderr, "Usage: %s --daemon | up | down | mute | micmute\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "--daemon") != 0) {
        if (strcmp(argv[1], "up") && strcmp(argv[1], "down") &&
            strcmp(argv[1], "mute") && strcmp(argv[1], "micmute")) {
            fprintf(stderr, "Usage: %s --daemon | up | down | mute | micmute\n", argv[0]);
        return 1;
            }

            struct stat st;
            if (stat(g_pipepath, &st) != 0 || !S_ISFIFO(st.st_mode)) return 0;

            int fd = open(g_pipepath, O_RDWR | O_NONBLOCK);
        if (fd < 0) return 0;

        char msg[16];
        int len = snprintf(msg, sizeof msg, "%s\n", argv[1]);
        write(fd, msg, (size_t)len);
        close(fd);
        return 0;
    }

    run_daemon();
    return 0;
}
