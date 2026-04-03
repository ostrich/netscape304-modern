#define _GNU_SOURCE

#include <arpa/inet.h>
#include <netdb.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

/* Netscape copy-relocates these old libc globals with fixed sizes. */
unsigned char _res[0x180];
const char *_sys_errlist[124];
int _sys_nerr = 124;

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

struct hostent *gethostbyname(const char *name) {
  char cmd[512];
  char line[512];
  char ip[INET_ADDRSTRLEN];
  FILE *fp;
  struct in_addr addr;
  size_t i;

  shim_log("gethostbyname(%s)", name ? name : "(null)");
  if (!name || !*name) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  for (i = 0; name[i]; i++) {
    if (!((name[i] >= 'a' && name[i] <= 'z') ||
          (name[i] >= 'A' && name[i] <= 'Z') ||
          (name[i] >= '0' && name[i] <= '9') ||
          name[i] == '.' || name[i] == '-')) {
      shim_log("refusing to resolve suspicious hostname: %s", name);
      h_errno = HOST_NOT_FOUND;
      return NULL;
    }
  }

  snprintf(cmd, sizeof(cmd), "/usr/bin/getent ahostsv4 '%s' 2>/dev/null", name);
  fp = popen(cmd, "r");
  if (!fp) {
    h_errno = TRY_AGAIN;
    return NULL;
  }

  if (!fgets(line, sizeof(line), fp)) {
    pclose(fp);
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  pclose(fp);
  if (sscanf(line, "%15s", ip) != 1) {
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

  if (!addr || type != AF_INET || len < (socklen_t)sizeof(struct in_addr)) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  if (!inet_ntop(AF_INET, addr, ip, sizeof(ip))) {
    h_errno = HOST_NOT_FOUND;
    return NULL;
  }

  shim_log("reverse lookup fallback %s", ip);
  return build_hostent_from_ipv4(ip, *(const uint32_t *)addr);
}
