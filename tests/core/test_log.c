#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

#include "shiro_log.h"
#include "test_util.h"

typedef struct writer {
    const char *path;
    int ok;
} writer;

static void *write_lines(void *context) {
    writer *w = context;
    w->ok = 1;
    for (int i = 0; i < 50; ++i)
        if (shiro_log_append(w->path, "complete line\n", 14, 65536) != SHIRO_OK) w->ok = 0;
    return NULL;
}

static void expect_file(const char *path, const char *content) {
    char buf[128];
    struct stat info;
    int fd = open(path, O_RDONLY);
    CHECK(fd >= 0);
    if (fd < 0) return;
    ssize_t n = read(fd, buf, sizeof(buf));
    CHECK_EQ_INT(n, strlen(content));
    if (n >= 0 && (size_t)n == strlen(content)) CHECK_MEM(buf, content, (size_t)n);
    CHECK_EQ_INT(fstat(fd, &info), 0);
    CHECK_EQ_INT(info.st_mode & 0777, 0600);
    close(fd);
}

int main(void) {
    char directory[] = "/tmp/shiro-log-test.XXXXXX";
    char path[128], previous[132], link[128];
    CHECK(mkdtemp(directory) != NULL);
    snprintf(path, sizeof(path), "%s/app.log", directory);
    snprintf(previous, sizeof(previous), "%s.1", path);
    snprintf(link, sizeof(link), "%s/link", directory);
    CHECK_EQ_INT(shiro_log_append(path, "", 0, 8), SHIRO_OK);
    CHECK_EQ_INT(access(path, F_OK), -1);
    CHECK_EQ_INT(shiro_log_append(path, "one\n", 4, 8), SHIRO_OK);
    CHECK_EQ_INT(shiro_log_append(path, "two\n", 4, 8), SHIRO_OK);
    expect_file(path, "one\ntwo\n");
    CHECK_EQ_INT(shiro_log_append(path, "three\n", 6, 8), SHIRO_OK);
    expect_file(previous, "one\ntwo\n");
    expect_file(path, "three\n");
    CHECK_EQ_INT(shiro_log_append(path, "12345678", 8, 8), SHIRO_OK);
    expect_file(previous, "three\n");
    expect_file(path, "12345678");
    CHECK_EQ_INT(shiro_log_append(path, "too long!", 9, 8), SHIRO_E_ARG);
    expect_file(path, "12345678");
    CHECK_EQ_INT(symlink(path, link), 0);
    CHECK_EQ_INT(shiro_log_append(link, "evil", 4, 8), SHIRO_E_STORAGE);
    expect_file(path, "12345678");
    CHECK_EQ_INT(shiro_log_append(directory, "x", 1, 8), SHIRO_E_STORAGE);
    CHECK_EQ_INT(shiro_log_append(NULL, "x", 1, 8), SHIRO_E_ARG);
    CHECK_EQ_INT(shiro_log_append(path, NULL, 0, 8), SHIRO_E_ARG);
    CHECK_EQ_INT(shiro_log_append(path, "x", 1, 0), SHIRO_E_ARG);
    unlink(path);
    writer writers[4];
    pthread_t threads[4];
    for (size_t i = 0; i < 4; ++i) {
        writers[i].path = path; writers[i].ok = 0;
        CHECK_EQ_INT(pthread_create(&threads[i], NULL, write_lines, &writers[i]), 0);
    }
    for (size_t i = 0; i < 4; ++i) {
        CHECK_EQ_INT(pthread_join(threads[i], NULL), 0);
        CHECK(writers[i].ok);
    }
    char lines[2801] = {0};
    int fd = open(path, O_RDONLY);
    CHECK(fd >= 0);
    CHECK_EQ_INT(read(fd, lines, sizeof(lines)), 2800);
    close(fd);
    for (size_t i = 0; i < 200; ++i) CHECK_MEM(lines + i * 14, "complete line\n", 14);
    unlink(path); unlink(previous); unlink(link); rmdir(directory);
    return test_finish("log");
}
