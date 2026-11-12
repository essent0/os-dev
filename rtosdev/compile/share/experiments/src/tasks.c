#include "experiment.h"

static int tasks_run( void )
{
    int count = rtosdev_print_tasks();

    return count >= 2 ? 0 : 1;
}

RTOSDEV_EXPERIMENT( tasks, tasks_run );
