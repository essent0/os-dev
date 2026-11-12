#ifndef RTOSDEV_EXPERIMENT_H
#define RTOSDEV_EXPERIMENT_H

#include "console.h"

typedef int ( * rtosdev_experiment_fn )( void );

typedef struct rtosdev_experiment
{
    const char * name;
    rtosdev_experiment_fn fn;
} rtosdev_experiment_t;

/* One entry per guest program. The name is what ./boot.sh NAME runs. */
#define RTOSDEV_EXPERIMENT( nm, func )                                  \
    static const rtosdev_experiment_t rtosdev_exp_##nm                  \
    __attribute__( ( used, section( "rtosdev_experiments" ), aligned( 8 ) ) ) = \
    {                                                                   \
        #nm, func                                                       \
    }

const rtosdev_experiment_t * rtosdev_find_experiment( const char * name );
void rtosdev_list_experiments( void );

#endif
