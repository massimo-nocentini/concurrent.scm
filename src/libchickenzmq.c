

#include <stdio.h>
#include <chicken/chicken.h>
#include <pthread.h>
#include <zmq.h>

extern C_word C_zmq_ctx_new(C_word x)
{
    void *ctx = zmq_ctx_new();

    C_word *ptr = C_alloc(C_SIZEOF_POINTER);

    return C_mpointer(&ptr, ctx);
}

void *pthread_create_callback(void *arg)
{
    C_word thunk = (C_word)arg;

    C_word *list = C_alloc(C_SIZEOF_LIST(0));

    C_word result;

    result = C_callback (thunk, 0);
    // int ret = CHICKEN_apply(thunk, C_list(&list, 0), &result);

    // printf("ret: %d\n", ret);

    return (void *)result;
}

extern C_word C_pthread_create(C_word thunk)
{
    pthread_t *th = (pthread_t *)malloc(sizeof(pthread_t));

    pthread_create(th, NULL, pthread_create_callback, (void *)thunk);

    C_word *ptr = C_alloc(C_SIZEOF_POINTER);

    return C_mpointer(&ptr, th);
}