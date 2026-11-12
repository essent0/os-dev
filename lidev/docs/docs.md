linux/fs/namei.c — reading map (Linux 7.3)
==========================================

This file is the VFS pathname resolver. open, stat, mkdir, unlink, rename,
symlink, link, readlink, and almost every other syscall that takes a path
ends up here. The per-filesystem namei.c files (ext4, xfs, ...) do not walk
paths. They implement the directory methods this file calls: ->lookup,
->create, ->mkdir, ->unlink, ->rename, ->get_link.

A path string is turned into a struct path { struct vfsmount *mnt; struct
dentry *dentry; }. Everything after that — permission checks, opening,
creating, removing — is done on that pair. The walk never calls into a
filesystem until the dcache misses.

The file has three jobs, in order:

  1. Copy the caller's pathname into a kernel struct filename.
  2. Walk it, component by component, into a struct path.
  3. Perform the operation on the final parent and the final component.


What to hold in your head
-------------------------

struct nameidata (around line 728) is the walk state, hung off
current->nameidata for the duration of the lookup:

  path          where the walk is standing now (mnt + dentry)
  inode         path.dentry->d_inode, cached so the hot path skips a load
  last          the component just parsed (struct qstr: name, len, hash)
  last_type     LAST_NORM, LAST_DOT, LAST_DOTDOT, or LAST_ROOT
  root          the walk's root. Usually current->fs->root. For
                LOOKUP_BENEATH / LOOKUP_IN_ROOT it is the starting dirfd,
                and ".." is not allowed to climb past it.
  flags         LOOKUP_* bits from include/linux/namei.h
  seq, m_seq,   seqcounts sampled so an RCU walk can notice that a dentry,
  r_seq         a mount, or a rename changed under it
  stack         saved symlink targets. Two slots live inside the struct
                (EMBEDDED_LEVELS). Longer chains are kmalloc'd, capped by
                MAXSYMLINKS.

A walk is either RCU (LOOKUP_RCU set: no refcounts, no inode locks, seqcounts
only) or ref-walk (real dget/mntget, locks allowed). The public entry points
always try RCU first.


The walk
--------

filename_lookup() is the usual "turn this path into a struct path" entry.
It retries three times:

  1. path_lookupat() with LOOKUP_RCU.
  2. On -ECHILD, the same walk with references.
  3. On -ESTALE, again with LOOKUP_REVAL, which tells ->d_revalidate()
     not to trust its cache.

do_file_open() uses the same ladder around path_openat().

path_lookupat() is:

  path_init()        choose the starting directory
  link_path_walk()   consume every component except the last
  lookup_last()      step into the last component
  complete_walk()    drop out of RCU and revalidate the result

path_init() decides where "here" is:

  - A preset root (nd_jump from a caller, or do_file_open_root) is used as-is.
  - A leading '/' jumps to current->fs->root, unless LOOKUP_IN_ROOT is set,
    in which case the dirfd is the root and the slash is not special.
  - Otherwise the start is AT_FDCWD (current->fs->pwd) or the dirfd.
  - LOOKUP_IS_SCOPED (LOOKUP_BENEATH | LOOKUP_IN_ROOT) pins nd->root to that
    start, so the walk cannot escape it. complete_walk() checks
    path_is_under() before returning.

link_path_walk() is the loop to learn. For each component it:

  1. may_lookup(): MAY_EXEC on the directory you are in. Search permission,
     not read permission. In RCU mode the check is passed MAY_NOT_BLOCK;
     if the filesystem cannot answer without sleeping, the walk drops to
     ref-walk.
  2. hash_name(): hash the component up to the next '/' or NUL, one word
     at a time when CONFIG_DCACHE_WORD_ACCESS is on. The hash is salted
     with the parent dentry pointer, because that is the dcache key.
     A one-word component that is "." or ".." is recognized here and
     stored as LAST_DOT / LAST_DOTDOT.
  3. If a filesystem sets DCACHE_OP_HASH (case-insensitive dirs), call
     ->d_hash to replace that hash.
  4. If this is the last component of the original path, stop. nd->last
     holds it and LOOKUP_PARENT is cleared. The caller decides whether
     to step into it.
  5. Otherwise walk_component() and, if that landed on a symlink, switch
     the cursor to the link body and keep going.

walk_component() is one step:

  "." and ".." go through handle_dots(). ".." uses follow_dotdot().
  At a mount root it climbs to the parent mount (choose_mountpoint).
  At nd->root it stays put. LOOKUP_BENEATH turns that into -EXDEV / -ECHILD.
  A mount-root ".." also checks path_connected(), which catches a rename
  that moved a directory out from under a bind mount.

  A normal name goes through lookup_fast(). That is __d_lookup_rcu() or
  __d_lookup(), then ->d_revalidate(). NULL means "not in the cache";
  the walk then takes the parent inode shared (i_rwsem) and calls
  lookup_slow() -> __lookup_slow() -> d_alloc_parallel() and, on a fresh
  in-lookup dentry, inode->i_op->lookup(). That is the first time a
  specific filesystem is asked about a name.

  step_into() advances nd->path onto the found dentry. The common case is
  compiled inline: RCU walk, not a mountpoint, not a symlink. Anything
  else goes to step_into_slowpath(), which calls handle_mounts() and, for
  a symlink that should be followed, pick_link().


Symlinks
--------

Following is iterative. pick_link() pushes the link's struct path on
nd->stack and returns the link body as the new string to parse. The
remaining unparsed tail of the current path is saved beside it. When a
link body is exhausted, link_path_walk() pops that tail and continues.
Absolute link text ("/...") calls nd_jump_root(). A filesystem "magic"
link (procfd) calls nd_jump_link() to jump straight to a struct path
instead of returning text.

Intermediate components are always followed. The final component is
followed only when LOOKUP_FOLLOW is set, or when the name has a trailing
slash (which also forces LOOKUP_DIRECTORY). Creation and removal use
path_parentat(), which never steps into the last component, so they do
not follow a symlink there.

Limits: total_link_count >= MAXSYMLINKS returns -ELOOP. So does
LOOKUP_NO_SYMLINKS, and a mount with MNT_NOSYMFOLLOW. may_follow_link()
enforces the protected_symlinks sysctl (a sticky world-writable directory
may not be used to follow a link owned by someone else).


RCU walk and why -ECHILD exists
-------------------------------

Under LOOKUP_RCU the walk holds rcu_read_lock() and nothing else. Dentries
can be freed, renamed, or unhashed concurrently. Each dentry has a seqcount
(d_seq). The walk samples it when it arrives and rechecks it before
trusting the inode, the parent pointer, or the child it just found.
mount_lock and rename_lock are sampled once in path_init() (m_seq, r_seq)
and rechecked when crossing a mount or resolving "..".

If a seqcount changed, the function returns -ECHILD. That does not mean
the path is bad. It means "this attempt raced; throw it away and redo the
whole walk with references." filename_lookup() and do_file_open() are the
places that restart.

try_to_unlazy() is the other exit from RCU mode. It takes real references
on nd->path, the root, and any stacked links, then checks the seqcounts
one last time. Success means the walk continues with locks allowed (a
permission check that needs to sleep, a missed dcache entry, an atime
update). Failure is also -ECHILD.

complete_walk() always unlazies before returning a path to the caller. If
the walk jumped (a "..", an absolute symlink, nd_jump_link — ND_JUMPED),
and the dentry has DCACHE_OP_WEAK_REVALIDATE, it calls ->d_weak_revalidate().
Failure becomes -ESTALE, which triggers the LOOKUP_REVAL retry.


Two shapes of lookup
--------------------

path_lookupat() wants the final object. stat, permission checks, O_PATH,
and plain open use it (open swaps lookup_last for open_last_lookups).

path_parentat() stops after link_path_walk(). The caller holds the parent
directory and the final qstr, then looks that name up itself while holding
the parent's inode lock. mkdir, unlink, rmdir, mknod, symlink, link, and
rename all work this way. The last component of a creating or removing
call is never followed. That is the rule from the comment near the top of
the file: inside the path, always follow; in the last component of a
create, remove, or rename, never follow.

LOOKUP_* flags worth knowing (include/linux/namei.h):

  LOOKUP_FOLLOW        follow a trailing symlink
  LOOKUP_DIRECTORY     result must be a directory
  LOOKUP_PARENT        set during link_path_walk; cleared before return
  LOOKUP_RCU           lockless attempt
  LOOKUP_REVAL         force revalidation
  LOOKUP_CREATE/EXCL   last component is being created
  LOOKUP_OPEN          last component is being opened
  LOOKUP_NO_SYMLINKS   openat2 RESOLVE_NO_SYMLINKS
  LOOKUP_NO_MAGICLINKS RESOLVE_NO_MAGICLINKS
  LOOKUP_NO_XDEV       RESOLVE_NO_XDEV
  LOOKUP_BENEATH       RESOLVE_BENEATH
  LOOKUP_IN_ROOT       RESOLVE_IN_ROOT
  LOOKUP_CACHED        dcache only; requires RCU
  LOOKUP_DOWN          traverse a mount on the starting point
  LOOKUP_MOUNTPOINT    traverse a mount on the final point


Open
----

path_openat() is the same walk with a different last step. After
link_path_walk(), open_last_lookups() handles the final component:

  - lookup_fast_for_open() for the cached case.
  - On a miss, lookup_open() takes the parent shared or exclusive and
    either looks the name up or, if the filesystem implements it, calls
    ->atomic_open() so lookup and open happen under one lock.
  - A trailing symlink drops LOOKUP_OPEN|CREATE|EXCL and returns the link
    body, and the outer loop in path_openat() keeps walking.

do_open() then runs may_open() (type checks, append-only, device node
policy, O_NOATIME), vfs_open(), and O_TRUNC via handle_truncate().
O_TMPFILE and O_PATH skip that last-component path and use do_tmpfile()
and do_o_path().


The rest of the file
--------------------

Lines 1–700 copy pathnames in (getname, putname) and implement the
permission helpers the walk and the VFS operations share:
generic_permission(), inode_permission(), sb_permission(). These are
idmap-aware. An idmapped mount passes its mnt_idmap; everyone else passes
nop_mnt_idmap.

Lines 1200–1460 are the sticky-directory hardening sysctls:
protected_symlinks, protected_hardlinks, protected_fifos, protected_regular.
may_follow_link(), may_linkat(), may_create_in_sticky().

Lines 1465–1760 follow mounts: follow_up(), follow_down(), automounts.

Lines 3000–4200 are locked lookup helpers used by creating and removing
syscalls: lookup_one(), start_creating(), start_removing(),
start_renaming(), lock_rename(). The parent i_rwsem is held exclusive
before ->lookup() is called for a create or unlink. d_alloc_parallel()
is what lets the shared (LOOKUP_SHARED) lookup in lookup_slow() race
safely with an exclusive creator.

From vfs_create() to the end are the operations themselves, each thin:

  filename_*at()    walk to the parent, lock it, look up the last name
  vfs_*()           permission check, security hook, then the filesystem
                    inode operation, then the dcache update

  vfs_create, vfs_mknod, vfs_mkdir, vfs_rmdir, vfs_unlink,
  vfs_symlink, vfs_link, vfs_rename

vfs_rename() is the locking puzzle. Two directories, lock ordering, the
ancestor check (you cannot rename a directory under itself), and
s_vfs_rename_mutex when the parents differ. Read it after the walk makes
sense, not before.

The tail of the file (vfs_readlink, page_get_link, page_symlink) is the
generic "symlink body lives in the page cache" implementation that
filesystems plug into inode->i_op->get_link.


Suggested reading order
-----------------------

  1. struct nameidata, path_init, link_path_walk, walk_component.
  2. lookup_fast, __lookup_slow, and the -ECHILD retry in filename_lookup.
  3. step_into, pick_link, handle_dots.
  4. path_lookupat versus path_parentat. Pick filename_mkdirat and
     filename_unlinkat and see how they consume the parent.
  5. path_openat, open_last_lookups, do_open.
  6. vfs_rename last.

While reading, track one concrete path on paper, for example
openat(AT_FDCWD, "a/b/c", O_RDONLY) where b is a symlink to "/x".
Mark which function consumes "a", which consumes the symlink, which
consumes "c", and which of the three retry attempts you are in.
