/*******************************************************************************

    Atomics (thread-safe operations)
    for debugging use


*******************************************************************************/

module thread_utils.Atomics;

/******************************************************************************

    Atomic Compare and Swap

    Used to set a variable to a value in a thread-safe way
    Returns: the value found at the point of read
             so if it equals expected the cas was sucsessful
    Note:
    this function is intended for debugging purposes only

******************************************************************************/

public extern (C) int cas (int* val, int expected, int desired)
{
    version (X86_64)
    {
        asm
        {
            // RDI is val_ptr
            // ESI is expected
            // EDX is desired
            naked;
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
            mov ECX, dword ptr [ESP+12]; // ECX is desired
            lock; cmpxchg dword ptr [EDX], ECX;
            ret ;
            db 0x0f, 0x1f, 0x00; // 3byte nop
        }
    }
    else
        static assert("No compare and swap for this platform");
}

unittest
{
    void testCas ()
    {
        int a = 1;
        int b = 2;
        int c = 3;
        int d = 4;

        assert(cas(&c, 3, 6) == 3);
        assert(cas(&c, 3, 12) == 6);
        assert(cas(&b, 2, 8) == 2);
        assert(cas(&b, 8, 3) == 8);
        assert(cas(&d, 4, ushort.max+64) == 4);
        assert(a == 1 && b == 3 && c == 6 && d == ushort.max + 64);
    }

    testCas();
}

/******************************************************************************

    Increments the value referenced by the pointer atomically
    (syncronized among cpu-cores)

    Note:
    This function is intended for debugging purpose only

******************************************************************************/

public extern (C) void atomicInc (int* val)
{
    version (X86_64)
    {
        asm
        {
            naked;
            lock; inc dword ptr [RDI];
            ret ;
        }
    }
    else version (X86)
    {
        asm
        {
            naked ;
            mov EDX, dword ptr [ESP+4];
            lock; inc dword ptr [EDX];
            nop ; // for the ret to be aligned
            ret ;
            nop ; // so dmd does not emit 0x0000
       }
    }
    else
        static assert("No atomic increment for this platform");
}

unittest
{
    void testAtomicInc ()
    {
        int a = 1;
        int b = 2;
        int c = 3;
        int d = 4;

        atomicInc(&c);
        assert(a == 1 && b == 2 && c == 4 && d == 4);
        atomicInc(&d);
        assert(a == 1 && b == 2 && c == 4 && d == 5);
    }

    testAtomicInc();
}
