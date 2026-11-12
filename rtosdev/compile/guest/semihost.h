#ifndef RTOSDEV_SEMIHOST_H
#define RTOSDEV_SEMIHOST_H

#include <stddef.h>

/* 0 on success. The buffer is NUL-terminated. */
int semihost_cmdline( char * buf, size_t len );
void semihost_exit( int status );

#endif
