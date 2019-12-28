module thread_utils.FastThreadId;

import core.sys.posix.pthread;
import core.stdc.stdio;

extern (C) size_t gettid();

void main()
{
    pthread_t[200] threads;
    while(true)
    {
        foreach(i, ref _; threads)
        {
            if(pthread_create(&threads[i], null, &thread_cb, cast(void*)(i + 1))) {
                fprintf(stderr, "Error creating thread\n");
            }
        }

        uint ctr;
        void* retval;

        foreach(i, ref _; threads)
        {
            pthread_join(threads[i], &retval);
            if(retval == null) {
                fprintf(stderr, "Well If guess we fucked up\n");
                assert(0);
            }
            ctr += *(cast(uint*) &retval);
        }
        printf("tid retrival took %f ticks per thread\n", ctr / cast(float)threads.length);
    }
}

void lock()
{
}

extern (C) void* thread_cb(void* pData)
{
    uint tsc_begin;
    uint tsc_end;
//    lock();
    asm { rdtsc; mov tsc_begin, EAX; }
//    int threadN = cast(int)pData;
//    auto ftid = fastThreadId();
//    auto stid  = ((pthread_self() >> 8) & uint.max);
//    auto stid = ftid;
//    int retval = ftid == stid;
    //printf("ThreadN: %d fastThreadId: %p pthread_self: %p equal: %s\n",
    //    threadN, ftid, stid, (retval ? "true".ptr : "false".ptr)
    //);
    asm { rdtsc; mov tsc_end, EAX; }
    return cast(void*) tsc_end - tsc_begin;
//    scope(exit) unlock();
}


extern (C) int slowThreadId()
{
   version (X86_64)
        return cast(int) ((pthread_self() >> 8) & uint.max);
    else version (X86)
        return pthread_self();
}

extern (C) int fastThreadId()
{
    version (linux)
    {
        version (X86)
        {
            asm
            {
                naked;
                mov EAX, dword ptr GS:0x0;
                ret ;
            }
        }
        else version (X86_64)
        {
            asm
            {
                naked;
                db 0x64, 0x48, 0x8b, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00;
                // mov RAX, qword ptr FS:0x0; But dmds iasm cannot do that :(
                shr RAX, 8;
                // the first byte is always 0 due to alignment
                ret ;
            }
        }
    }
    else static assert ("Your OS is currently unsupported");
}
