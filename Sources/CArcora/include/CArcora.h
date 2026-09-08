#ifndef CARCORA_H
#define CARCORA_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *path;
    const char *link;
    int64_t size;
    int64_t modified;
    int directory;
    int encrypted;
    int unsafe_type;
} arc_entry;
// Callbacks run synchronously on the calling thread. Nonzero cancels the operation.
typedef int (*arc_entry_callback)(const arc_entry *, void *);
typedef int (*arc_progress_callback)(uint64_t bytes, uint64_t entries, void *);
const char *arc_archive_version(void);
int arc_archive_list(const char *source, const char *password, uint64_t max_entries,
                     arc_entry_callback callback, void *context, char *error, size_t error_len);
int arc_archive_read(const char *source, const char *password, const char *destination,
                     uint64_t max_bytes, uint64_t max_entries, int test_only,
                     arc_entry_callback filter, arc_progress_callback callback, void *context, char *error, size_t error_len);
int arc_safe_relative_path(const char *path);
int arc_rename_exclusive(const char *source, const char *destination);
void arc_zero(void *buffer, size_t count);
void arc_ignore_sigpipe(void);
int arc_copy_quarantine(const char *source, const char *destination);
#ifdef __cplusplus
}
#endif
#endif
