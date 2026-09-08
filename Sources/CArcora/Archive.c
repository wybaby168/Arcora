#define _GNU_SOURCE
#include "CArcora.h"
#include <archive.h>
#include <archive_entry.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <locale.h>
#ifdef __APPLE__
#include <sys/xattr.h>
#include <sys/attr.h>
#include <xlocale.h>
#else
#include <sys/syscall.h>
#include <linux/fs.h>
#endif

// libarchive converts filenames through the current C locale. Foundation does
// not initialize that locale from LANG. Use a per-thread UTF-8 locale instead
// of setlocale(), which would race with other callers in an embedding process.
struct utf8_locale { locale_t value; locale_t previous; };
static struct utf8_locale begin_utf8(void) {
    struct utf8_locale scope={0,0};
    scope.value=newlocale(LC_CTYPE_MASK,"en_US.UTF-8",(locale_t)0);
    if (!scope.value) scope.value=newlocale(LC_CTYPE_MASK,"C.UTF-8",(locale_t)0);
    if (scope.value) scope.previous=uselocale(scope.value);
    return scope;
}
static void end_utf8(struct utf8_locale scope) {
    if (scope.value) { uselocale(scope.previous); freelocale(scope.value); }
}

static int fail(char *out, size_t n, const char *message) {
    if (out && n) snprintf(out, n, "%s", message ? message : "Archive operation failed");
    return -1;
}
const char *arc_archive_version(void) { return archive_version_string(); }
void arc_zero(void *ptr, size_t n) { volatile unsigned char *p=ptr; while(n--) *p++=0; }
void arc_ignore_sigpipe(void) { signal(SIGPIPE, SIG_IGN); }

int arc_safe_relative_path(const char *p) {
    if (!p || !*p || *p=='/' || *p=='\\' || strlen(p)>32768) return 0;
    const char *part=p;
    for (const unsigned char *c=(const unsigned char *)p;;c++) {
        if (*c=='\\' || *c==':' || (*c && (*c<32 || *c==127))) return 0;
        if (*c=='/' || *c==0) {
            size_t n=(const char *)c-part;
            if (n==2 && part[0]=='.' && part[1]=='.') return 0;
            // Harmless leading "./" is accepted for standard tar archives.
            if (*c==0) break;
            part=(const char *)c+1;
        }
    }
    return 1;
}

static struct archive *reader(const char *source, const char *password, char *err, size_t n) {
    struct archive *a=archive_read_new();
    if (!a) { fail(err,n,"Cannot allocate archive reader"); return NULL; }
    archive_read_support_filter_all(a);
    // Register container formats explicitly. In particular, do not register
    // mtree: it is a filesystem description, not a self-contained archive.
    archive_read_support_format_7zip(a);
    archive_read_support_format_ar(a);
    archive_read_support_format_cab(a);
    archive_read_support_format_cpio(a);
    archive_read_support_format_iso9660(a);
    archive_read_support_format_lha(a);
    archive_read_support_format_rar(a);
#if ARCHIVE_VERSION_NUMBER >= 3004000
    archive_read_support_format_rar5(a);
#endif
    archive_read_support_format_tar(a);
    archive_read_support_format_xar(a);
    archive_read_support_format_zip(a);
    // No raw-format fall-through: arbitrary bytes are not accepted as an archive.
    if (password && *password) archive_read_add_passphrase(a,password);
    if (archive_read_open_filename(a,source,65536)!=ARCHIVE_OK) {
        fail(err,n,archive_error_string(a)); archive_read_free(a); return NULL;
    }
    return a;
}
static int unsafe_entry(struct archive_entry *e) {
    mode_t t=archive_entry_filetype(e);
    return (t!=AE_IFREG && t!=AE_IFDIR) || archive_entry_hardlink(e)!=NULL || archive_entry_symlink(e)!=NULL;
}

int arc_archive_list(const char *source, const char *password, uint64_t max_entries,
                     arc_entry_callback callback, void *ctx, char *err, size_t n) {
    struct utf8_locale locale=begin_utf8();
    struct archive *a=reader(source,password,err,n);
    if (!a) { end_utf8(locale); return -1; }
    struct archive_entry *e=NULL;
    uint64_t count=0;
    int status, result=0;
    while ((status=archive_read_next_header(a,&e))==ARCHIVE_OK) {
        if (++count>max_entries) { result=fail(err,n,"Entry limit exceeded"); break; }
        const char *path=archive_entry_pathname_utf8(e);
        if (!path) path=archive_entry_pathname(e);
        if (!path) { result=fail(err,n,"Unrepresentable archive filename"); break; }
        arc_entry item={path,archive_entry_symlink(e),archive_entry_size(e),
            archive_entry_mtime(e),archive_entry_filetype(e)==AE_IFDIR,
            archive_entry_is_encrypted(e)>0,unsafe_entry(e)};
        if (callback && callback(&item,ctx)) { result=fail(err,n,"Cancelled"); break; }
        status=archive_read_data_skip(a);
        if (status<ARCHIVE_OK) { result=fail(err,n,archive_error_string(a)); break; }
    }
    if (!result && status!=ARCHIVE_EOF) result=fail(err,n,archive_error_string(a));
    archive_read_free(a);
    end_utf8(locale);
    return result;
}

// Return a held fd for the parent. Every component is opened with O_NOFOLLOW;
// no archive-supplied symlink, hardlink, device or absolute path is ever written.
static int parent_fd(int root, const char *path, char **leaf, char *err, size_t n) {
    char *copy=strdup(path);
    if (!copy) return fail(err,n,"Out of memory");
    size_t len=strlen(copy);
    while (len>0 && copy[len-1]=='/') copy[--len]=0;
    int fd=dup(root);
    if (fd<0) { free(copy); return fail(err,n,strerror(errno)); }
    char *save=NULL, *part=strtok_r(copy,"/",&save);
    if (!part) { close(fd); free(copy); return fail(err,n,"Empty path"); }
    for (;;) {
        char *next=strtok_r(NULL,"/",&save);
        if (!next) {
            *leaf=strdup(part);
            free(copy);
            if (!*leaf) { close(fd); return fail(err,n,"Out of memory"); }
            return fd;
        }
        if (strcmp(part,".")!=0) {
            if (mkdirat(fd,part,0700)<0 && errno!=EEXIST) {
                close(fd); free(copy); return fail(err,n,strerror(errno));
            }
            int child=openat(fd,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if (child<0) { close(fd); free(copy); return fail(err,n,"Unsafe parent or inaccessible directory"); }
            close(fd); fd=child;
        }
        part=next;
    }
}

int arc_archive_read(const char *source,const char *password,const char *destination,
                     uint64_t max_bytes,uint64_t max_entries,int test_only,
                     arc_entry_callback filter,arc_progress_callback callback,void *ctx,char *err,size_t n) {
    int root=-1;
    if (!test_only) {
        root=open(destination,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        if (root<0) return fail(err,n,"Destination must be an existing real directory");
    }
    struct utf8_locale locale=begin_utf8();
    struct archive *a=reader(source,password,err,n);
    if (!a) { if(root>=0)close(root); end_utf8(locale); return -1; }
    uint64_t bytes=0,count=0;
    struct archive_entry *e=NULL;
    int status,result=0;
    char buffer[65536];
    while ((status=archive_read_next_header(a,&e))==ARCHIVE_OK) {
        if (++count>max_entries) { result=fail(err,n,"Entry limit exceeded"); break; }
        const char *path=archive_entry_pathname_utf8(e);
        if (!path) path=archive_entry_pathname(e);
        if (!arc_safe_relative_path(path) || unsafe_entry(e)) {
            result=fail(err,n,"Unsafe archive path or unsupported link/special file"); break;
        }
        // A root directory entry '.' is metadata, not an output file.
        if (archive_entry_filetype(e)==AE_IFDIR && (!strcmp(path,".") || !strcmp(path,"./"))) continue;
        if (filter) {
            arc_entry item={path,NULL,archive_entry_size(e),archive_entry_mtime(e),archive_entry_filetype(e)==AE_IFDIR,archive_entry_is_encrypted(e)>0,0};
            if (!filter(&item,ctx)) {
                status=archive_read_data_skip(a);
                if (status<ARCHIVE_OK) { result=fail(err,n,archive_error_string(a)); break; }
                continue;
            }
        }
        int output=-1,parent=-1;
        char *leaf=NULL;
        if (!test_only) {
            parent=parent_fd(root,path,&leaf,err,n);
            if (parent<0) { result=-1; break; }
            if (archive_entry_filetype(e)==AE_IFDIR) {
                if (mkdirat(parent,leaf,0700)<0 && errno!=EEXIST) result=fail(err,n,strerror(errno));
                int verify=openat(parent,leaf,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
                if (verify<0) result=fail(err,n,"Directory collision"); else close(verify);
            } else {
                output=openat(parent,leaf,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0600);
                if (output<0) result=fail(err,n,"Output already exists or cannot be created");
            }
            free(leaf); close(parent);
            if (result) break;
        }
        la_ssize_t got;
        while ((got=archive_read_data(a,buffer,sizeof(buffer)))>0) {
            if ((uint64_t)got>max_bytes || bytes>max_bytes-(uint64_t)got) {
                result=fail(err,n,"Expanded byte limit exceeded"); break;
            }
            bytes+=(uint64_t)got;
            if (output>=0) {
                ssize_t pos=0;
                while (pos<got) {
                    ssize_t written=write(output,buffer+pos,(size_t)(got-pos));
                    if (written<0 && errno==EINTR) continue;
                    if (written<=0) { result=fail(err,n,strerror(errno)); break; }
                    pos+=written;
                }
            }
            if (result || (callback && callback(bytes,count,ctx))) {
                if (!result) result=fail(err,n,"Cancelled");
                break;
            }
        }
        if (!result && got<0) result=fail(err,n,archive_error_string(a));
        if (output>=0) {
            // Never restore ownership, setuid, setgid, ACLs or archive xattrs.
            fchmod(output,0600 | (archive_entry_perm(e)&0111));
            struct timespec ts[2]={{archive_entry_mtime(e),0},{archive_entry_mtime(e),0}};
            futimens(output,ts);
            if (close(output)<0 && !result) result=fail(err,n,strerror(errno));
        }
        if (result) break;
        if (callback && callback(bytes,count,ctx)) { result=fail(err,n,"Cancelled"); break; }
    }
    if (!result && status!=ARCHIVE_EOF) result=fail(err,n,archive_error_string(a));
    archive_read_free(a);
    if(root>=0)close(root);
    end_utf8(locale);
    return result;
}

int arc_rename_exclusive(const char *source,const char *destination) {
#ifdef __APPLE__
    return renamex_np(source,destination,RENAME_EXCL);
#else
    return (int)syscall(SYS_renameat2,AT_FDCWD,source,AT_FDCWD,destination,RENAME_NOREPLACE);
#endif
}
int arc_copy_quarantine(const char *source,const char *destination) {
#ifdef __APPLE__
    char value[8192];
    ssize_t count=getxattr(source,"com.apple.quarantine",value,sizeof(value),0,XATTR_NOFOLLOW);
    if (count<0) return errno==ENOATTR ? 0 : -1;
    return setxattr(destination,"com.apple.quarantine",value,(size_t)count,0,XATTR_NOFOLLOW);
#else
    (void)source; (void)destination;
    return 0;
#endif
}
