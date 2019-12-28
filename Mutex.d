/*******************************************************************************

    Mutex (thread-safe lock)
    for debugging use

    Copyright: Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

*******************************************************************************/

module thread_utils.Mutex;

/******************************************************************************

   Aquire Mutex (Blocking) 

    This function will block until the mutex is aquired.

    It is recommended that you call this function if you would have
    had a busy wait loop anyway.

    Params: m = the mutex pointer

******************************************************************************/

import waveclean.util.Atomics;

extern (C) void aquireWaitForCurrentThread(Mutex* m)
{
//  
//    while(cas(cast(int*)m, 0, tid) != tid) { }
// cas deos not get inlined meaning we have to do the asm dance
    version (X86_64)
    {
        asm
        {
            // RDI is val_ptr
            // ESI is desired
            // EAX is expected
            naked;
            // FS:0x0 is the start of tls and therefore can be used as
            // unique identifier for the thread

            // mov RSI, qword ptr FS:0x0
            db 0x64, 0x48, 0x8b, 0x34, 0x25, 0x00, 0x00, 0x00, 0x00;
            // again dmd iasm cannot do this :)

            // we only want to do a cmgxchg of 32bit
            // therefore we shift the portion that is 
            // almost guranteed to be zero on 64bit out
            shr RSI, 8;
        Lbegin:
            xor EAX, EAX; // we are expecting zero
            lock; cmpxchg dword ptr [RDI], ESI;
            je Lend;
                rep; nop; // this is the pause opcode
                jmp Lbegin;
        Lend:
            ret ;
        }
    }
    else version (X86)
    {
        // TODO for some reason dmd1 -m32 bloats this function with nops
        asm
        {
            naked ;
            mov EDX, dword ptr [ESP+4]; // EDX is val_ptr
            // GS:0x0 is the start of tls and therefore usable as 
            // thread id
            mov ECX, dword ptr GS:0x0 ; // ECX is desired
        Lbegin:
            xor EAX, EAX;  // we are expecting zero
            lock; cmpxchg dword ptr [EDX], ECX;
            je Lend;
                rep; nop; // this is the pause opcode
                jmp Lbegin;
        Lend:
            ret ;
        }
    }
}


/******************************************************************************

    Aquire Mutex

    Used to aquire the mutex
    Params: m = the mutex pointer
            tid = your tid
    Returns: the tid of the holder
             so if it equals your tid, it was aquired

******************************************************************************/

extern (C) int aquire(Mutex* m, int tid)
{
//    return cas(cast(int*)m, 0, tid);
// cas deos not get inlined meaning we have to do the asm dance
    version (X86_64)
    {
        asm
        {
            // RDI is val_ptr
            // ESI is desired
            // EAX is expected
            naked;
            xor EAX, EAX; // we are expecting zero
            lock; cmpxchg dword ptr [RDI], ESI;
            ret ;
        }
    }
    else version (X86)
    {
        // TODO for some reason dmd1 -m32 bloats this function with nops
        asm
        {
            naked ;
            mov EDX, dword ptr [ESP+4];  // EDX is val_ptr
            mov ECX, dword ptr [ESP+8]; // ECX is desired
            xor EAX, EAX;  // we are expecting zero
            lock; cmpxchg dword ptr [EDX], ECX;
            ret ;
        }
    }
}

struct Mutex
{
    int holder; /// 0 means unlocked
}

/******************************************************************************

    Release Mutex

    Used to release the mutex
    Params: m = the mutex pointer
            tid = your tid
    Returns: the tid of the holder
             so if it equals your tid, it was released

******************************************************************************/

extern (C) int release(Mutex* m, int tid)
{
    debug
    {
        assert(cas(cast(int*)m, tid, 0) == tid,
            "releasing mutex failed we have a problem"
        );
    }
    else
    //    return cas(cast(int*)m, tid, 0);
    // This does not get inlined
    // so we have to do the asm dance again *sigh*
    version (X86_64)
    {
        asm
        {
            // RDI is val_ptr
            // ESI is expected
            // EDX is desired
            naked;
            xor EDX, EDX; // quickly zero EDX 
            mov EAX, ESI;
            lock; cmpxchg dword ptr [RDI], EDX;
            ret ;
        }
    }
    else version (X86)
    {
        // TODO for some reason dmd1 -m32 bloats this function with nops
        asm
        {
            naked ;
            mov EDX, dword ptr [ESP+4];  // EDX is val_ptr
            mov EAX, dword ptr [ESP+8];  // EAX is expected
            xor ECX, ECX; // ECX is desired in this case zero
            lock; cmpxchg dword ptr [EDX], ECX;
            ret ;
        }
    }

}

/******************************************************************************

    Unsyncronized check if Mutex is held

    Note:
        This is not thread-safe

    Params: m = the mutex pointer
            tid = your tid
    Returns: zero if held
             non-zero otherwise

******************************************************************************/

extern (C) bool quickIsReleased(Mutex* m)
{
    // written as asm to avoid codegen issue
    version (X86_64)
    {
        asm 
        {
            naked ;
            cmp    dword ptr [RDI],0x0;
            nop;
            sete   AL;
            nop;
            ret;
            nop;
        }
    }
    else
        return ((*cast(int*)m) == 0);
}


unittest {
    void testMutex ()
    {
        Mutex m; // starts out unlocked;
        assert(quickIsReleased(&m));
        aquire(&m, 21); // tid 21 aquires mutex
        assert(!quickIsReleased(&m));
        assert(aquire(&m, 20) == 21);
        // assert that aquire from a diffrent thread fails
        assert(release(&m, 20) == 21);
        assert(!quickIsReleased(&m));
        release(&m, 21);
        assert(quickIsReleased(&m));       
    }

    testMutex();
}
