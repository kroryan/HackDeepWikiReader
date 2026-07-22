#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// WebKitGTK reads WEBKIT_DISABLE_COMPOSITING_MODE while its shared library is
// loaded, before the Flutter runner's main() is called. This tiny executable
// is therefore the public bundle entry point: it sets the safe X11 mode and
// then replaces itself with the real Flutter process. Keeping both binaries
// beside each other preserves the normal $ORIGIN/lib bundle RPATH.
int main(int argc, char** argv) {
  (void)argc;

  char launcher_path[PATH_MAX];
  const ssize_t length =
      readlink("/proc/self/exe", launcher_path, sizeof(launcher_path) - 1);
  if (length < 0) {
    fprintf(stderr, "Could not locate HackDeepWikiReader launcher: %s\n",
            strerror(errno));
    return 127;
  }
  launcher_path[length] = '\0';

  char* filename = strrchr(launcher_path, '/');
  if (filename == NULL) {
    fputs("Could not resolve HackDeepWikiReader bundle directory\n", stderr);
    return 127;
  }
  filename[1] = '\0';

  char runner_path[PATH_MAX];
  const int written = snprintf(runner_path, sizeof(runner_path), "%s%s",
                               launcher_path, "hackdeepwikireader.real");
  if (written < 0 || written >= (int)sizeof(runner_path)) {
    fputs("HackDeepWikiReader bundle path is too long\n", stderr);
    return 127;
  }

  // Flutter's Linux embedder and WebKitGTK otherwise compete for an X11 GLX
  // drawable when the native ZIM view opens, and Xlib terminates the app with
  // BadAccess. Static offline ZIM pages do not need accelerated compositing.
  if (setenv("WEBKIT_DISABLE_COMPOSITING_MODE", "1", 1) != 0) {
    fprintf(stderr, "Could not configure WebKitGTK: %s\n", strerror(errno));
    return 127;
  }

  execv(runner_path, argv);
  fprintf(stderr, "Could not start %s: %s\n", runner_path, strerror(errno));
  return 127;
}
