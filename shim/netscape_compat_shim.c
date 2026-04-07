#define _GNU_SOURCE

#include <arpa/inet.h>
#include <netdb.h>
#include <resolv.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _res
#undef _res
#endif

/* Netscape copy-relocates these old libc globals with fixed sizes. */
unsigned char _res[0x180] __attribute__((aligned(16)));
const char *_sys_errlist[124];
int _sys_nerr = 124;

static char shim_sys_err_storage[124][128];

static int shim_debug_enabled(void) {
  static int initialized = 0;
  static int enabled = 0;
  if (!initialized) {
    enabled = (getenv("NETSCAPE_SHIM_DEBUG") != NULL);
    initialized = 1;
  }
  return enabled;
}

static void shim_log(const char *fmt, ...) {
  va_list ap;

  if (!shim_debug_enabled()) {
    return;
  }

  fputs("[netscape-shim] ", stderr);
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
  fflush(stderr);
}

__attribute__((constructor))
static void shim_init_compat_globals(void) {
  int i;

  memset(_res, 0, sizeof(_res));
  for (i = 0; i < _sys_nerr; ++i) {
    const char *msg = strerror(i);

    if (!msg) {
      msg = "Unknown error";
    }
    snprintf(shim_sys_err_storage[i], sizeof(shim_sys_err_storage[i]), "%s", msg);
    _sys_errlist[i] = shim_sys_err_storage[i];
  }
}

/* The binary calls __libc_init(argc, argv, envp) very early. */
void __libc_init(int argc, char **argv, char **envp) {
  (void)argc;
  (void)argv;
  (void)envp;
}

/*
 * Modern X servers can reject this early image probe with BadMatch.
 * The caller tolerates a NULL image, so fail softly instead.
 */
void *XGetImage(void *display,
                unsigned long drawable,
                int x,
                int y,
                unsigned int width,
                unsigned int height,
                unsigned long plane_mask,
                int format) {
  (void)display;
  (void)drawable;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
  (void)plane_mask;
  (void)format;
  return NULL;
}

int res_init(void) {
  shim_log("res_init()");
  memset(_res, 0, sizeof(_res));
  return 0;
}

static struct hostent shim_hostent;
static char *shim_aliases[] = { NULL };
static char *shim_addr_list[] = { NULL, NULL };
static char shim_name[256];
static uint32_t shim_addr;

static struct hostent *build_hostent_from_ipv4(const char *name, uint32_t addr_be) {
  memset(&shim_hostent, 0, sizeof(shim_hostent));
  memset(shim_name, 0, sizeof(shim_name));

  strncpy(shim_name, name, sizeof(shim_name) - 1);
  shim_addr = addr_be;

  shim_hostent.h_name = shim_name;
  shim_hostent.h_aliases = shim_aliases;
  shim_hostent.h_addrtype = AF_INET;
  shim_hostent.h_length = sizeof(shim_addr);
  shim_addr_list[0] = (char *)&shim_addr;
  shim_addr_list[1] = NULL;
  shim_hostent.h_addr_list = shim_addr_list;
  return &shim_hostent;
}

static int run_getent_first_token(const char *database,
                                  const char *key,
                                  char *token,
                                  size_t token_size) {
  int pipefd[2];
  pid_t pid;
  FILE *fp;
  int status;
  char line[512];
  char *argv[] = {
    "/usr/bin/getent",
    (char *)database,
    (char *)key,
    NULL
  };

  if (pipe(pipefd) != 0) {
    return -1;
  }

  pid = fork();
  if (pid < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    return -1;
  }

  if (pid == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);
    close(STDERR_FILENO);
    execv(argv[0], argv);
    _exit(127);
  }

  close(pipefd[1]);
  fp = fdopen(pipefd[0], "r");
  if (!fp) {
    close(pipefd[0]);
    waitpid(pid, NULL, 0);
    return -1;
  }

  line[0] = '\0';
  if (!fgets(line, sizeof(line), fp)) {
    fclose(fp);
    waitpid(pid, &status, 0);
    return -1;
  }

  fclose(fp);
  if (waitpid(pid, &status, 0) < 0) {
    return -1;
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    return -1;
  }
  if (sscanf(line, "%255s", token) != 1) {
    return -1;
  }
  token[token_size - 1] = '\0';
  return 0;
}

struct hostent *gethostbyname(const char *name) {
  char ip[INET_ADDRSTRLEN];
  struct in_addr addr;

  shim_log("gethostbyname(%s)", name ? name : "(null)");
  if (!name || !*name) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  if (run_getent_first_token("ahostsv4", name, ip, sizeof(ip)) != 0) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }
  if (inet_aton(ip, &addr) == 0) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  shim_log("resolved %s -> %s", name, ip);
  return build_hostent_from_ipv4(name, addr.s_addr);
}

struct hostent *gethostbyaddr(const void *addr, socklen_t len, int type) {
  char ip[INET_ADDRSTRLEN];
  char host[256];

  if (!addr || type != AF_INET || len < (socklen_t)sizeof(struct in_addr)) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  if (!inet_ntop(AF_INET, addr, ip, sizeof(ip))) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }
  if (run_getent_first_token("hosts", ip, host, sizeof(host)) != 0) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  shim_log("reverse lookup resolved %s -> %s", ip, host);
  return build_hostent_from_ipv4(host, *(const uint32_t *)addr);
}
