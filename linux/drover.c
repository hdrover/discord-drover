/*
 * drover - Linux port of Discord Drover (Direct / UDP mode only)
 *
 * Replicates the UDP trick from the Windows version:
 * Before the first 74-byte UDP send on any socket, two tiny packets
 * (payload 0x00 and 0x01) are injected to the same destination,
 * followed by a 50 ms pause.  This bypasses the UAE voice-chat block
 * without touching any proxy settings.
 *
 * Build:
 *   gcc -shared -fPIC -o drover.so drover.c -ldl -lpthread
 *
 * Use:
 *   LD_PRELOAD=/path/to/drover.so discord
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/uio.h>        /* struct iovec */
#include <pthread.h>
#include <time.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/*  Socket tracking table                                               */
/* ------------------------------------------------------------------ */

#define MAX_SOCKETS   8192
#define GC_AGE_SECS     30   /* drop entries older than this */

typedef struct {
    int      fd;
    int      is_udp;
    int      has_sent;
    time_t   created_at;
} SockEntry;

static SockEntry g_table[MAX_SOCKETS];
static int       g_count = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

/* ------------------------------------------------------------------ */
/*  Real function pointers                                              */
/* ------------------------------------------------------------------ */

static int     (*real_socket )(int, int, int)                                          = NULL;
static ssize_t (*real_sendto )(int, const void *, size_t, int,
                                const struct sockaddr *, socklen_t)                    = NULL;
static ssize_t (*real_sendmsg)(int, const struct msghdr *, int)                        = NULL;

static void ensure_hooks(void)
{
    if (!real_socket)  real_socket  = dlsym(RTLD_NEXT, "socket");
    if (!real_sendto)  real_sendto  = dlsym(RTLD_NEXT, "sendto");
    if (!real_sendmsg) real_sendmsg = dlsym(RTLD_NEXT, "sendmsg");
}

/* ------------------------------------------------------------------ */
/*  Table helpers (must be called with g_lock held)                     */
/* ------------------------------------------------------------------ */

static void gc_locked(void)
{
    time_t cutoff = time(NULL) - GC_AGE_SECS;
    for (int i = g_count - 1; i >= 0; i--) {
        if (g_table[i].created_at < cutoff)
            g_table[i] = g_table[--g_count];
    }
}

static int find_locked(int fd)
{
    for (int i = 0; i < g_count; i++)
        if (g_table[i].fd == fd) return i;
    return -1;
}

/* ------------------------------------------------------------------ */
/*  socket() hook — record whether this fd is UDP                       */
/* ------------------------------------------------------------------ */

int socket(int domain, int type, int protocol)
{
    ensure_hooks();
    int fd = real_socket(domain, type, protocol);
    if (fd < 0) return fd;

    /* SOCK_DGRAM is 2; mask off SOCK_NONBLOCK / SOCK_CLOEXEC flags */
    int is_udp = ((type & 0xf) == SOCK_DGRAM);

    pthread_mutex_lock(&g_lock);
    gc_locked();
    int idx = find_locked(fd);
    if (idx < 0) {
        idx = (g_count < MAX_SOCKETS) ? g_count++ : 0;
    }
    g_table[idx] = (SockEntry){ fd, is_udp, 0, time(NULL) };
    pthread_mutex_unlock(&g_lock);

    return fd;
}

/* ------------------------------------------------------------------ */
/*  Returns 1 (and marks sent) if this is the first send on a UDP sock  */
/* ------------------------------------------------------------------ */

static int claim_first_send(int fd)
{
    int ok = 0;
    pthread_mutex_lock(&g_lock);
    int idx = find_locked(fd);
    if (idx >= 0 && g_table[idx].is_udp && !g_table[idx].has_sent) {
        g_table[idx].has_sent = 1;
        ok = 1;
    }
    pthread_mutex_unlock(&g_lock);
    return ok;
}

/* ------------------------------------------------------------------ */
/*  The actual trick: two tiny probes then a 50 ms pause                */
/* ------------------------------------------------------------------ */

static void udp_trick(int fd, int flags,
                      const struct sockaddr *addr, socklen_t addrlen)
{
    uint8_t b0 = 0, b1 = 1;
    real_sendto(fd, &b0, 1, flags, addr, addrlen);
    real_sendto(fd, &b1, 1, flags, addr, addrlen);

    struct timespec ts = { 0, 50000000L }; /* 50 ms */
    nanosleep(&ts, NULL);
}

/* ------------------------------------------------------------------ */
/*  sendto() hook                                                       */
/* ------------------------------------------------------------------ */

ssize_t sendto(int fd, const void *buf, size_t len, int flags,
               const struct sockaddr *addr, socklen_t addrlen)
{
    ensure_hooks();

    if (len == 74 && addr && addrlen > 0 && claim_first_send(fd))
        udp_trick(fd, flags, addr, addrlen);

    return real_sendto(fd, buf, len, flags, addr, addrlen);
}

/* ------------------------------------------------------------------ */
/*  sendmsg() hook — Chromium / Electron sometimes uses this            */
/* ------------------------------------------------------------------ */

ssize_t sendmsg(int fd, const struct msghdr *msg, int flags)
{
    ensure_hooks();

    if (msg && msg->msg_name && msg->msg_namelen > 0) {
        /* sum iov lengths to get total payload size */
        size_t total = 0;
        for (size_t i = 0; i < (size_t)msg->msg_iovlen; i++)
            total += msg->msg_iov[i].iov_len;

        if (total == 74 && claim_first_send(fd))
            udp_trick(fd, flags,
                      (const struct sockaddr *)msg->msg_name,
                      (socklen_t)msg->msg_namelen);
    }

    return real_sendmsg(fd, msg, flags);
}
