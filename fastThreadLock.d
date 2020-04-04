import core.thread;
import core.time;

enum Platform
{
    Unsupported,

    X86_64,

}

version (linux)
{
    import core.sys.posix.pthread;
}
else
{
    static assert(0, "Platform unsupported");
}
immutable string readFence = ``;
immutable string writeFence = ``;


extern(C) uint GetThreadId()
{
    asm nothrow {
                db 0x64,  0x48, 0x8b, 0x0c, 0x25, 0x00, 0x00, 0x00, 0x00;
                // mov RCX, qword ptr FS:0x0; But dmds iasm cannot do that :(
                // rcx = thread_id

                shr RCX, 8;
                mov RAX, RCX;
    }
}

/// NOTE: I am aware how this function looks,
/// Given the tools I have (buggy iasm) this the best
string LockQueue(string lock, string retval = null)
{
    assert(__ctfe);
    return
        (retval ? `static assert(is(typeof(` ~ retval ~ `) == uint), "retval has to be a uint");` : ``) ~
`
    static assert(is(typeof(` ~ lock ~ `) == uint), "can only lock on uint");
    {
    enum lbl = mixin("\"L" ~ __LINE__.stringof ~ "\"");
    enum lockName = "` ~ lock ~ `";
    uint* lockPtr = &` ~lock ~ `;
    version (linux)
    {
        version (X86_64)
        {
            asm nothrow
            {
                push RAX;
                push RCX;
                push RDX;
                db 0x64,  0x48, 0x8b, 0x0c, 0x25, 0x00, 0x00, 0x00, 0x00;
                // mov RCX, qword ptr FS:0x0; But dmds iasm cannot do that :(
                // rcx = thread_id

                shr RCX, 8;

                // the first byte is always 0 due to alignment
            }
            mixin(lbl ~ ":" ~ "
            asm nothrow {
                xor RAX, RAX; // rax = 0
                mov RDX, [lockPtr]; // load ptr
                lock; cmpxchg dword ptr [RDX], ECX; // xchg()
                // xchg the lock value
             " ~
            ` ~ (retval ? `"mov ` ~ retval ~ `, EAX;"` : `""`) ~ `
            ~ "je " ~ lbl ~ ";
                // this code is eqivalent to
                // if (lock == 0) { lock = thread_id; retval = lock; }
                // else { retval = lock }
                pop RDX;
                pop RCX;
                pop RAX;
            }");
        }
        else static assert("Unsupported CPU");
    }
    else static assert("Unsupported OS");

    }
`;
}

string UnlockQueue(string lock)
{
    return "(*(&" ~ lock ~ ")) = 0;";
}

struct CopyQueueEntry
{
    void* dest;
    const (void)* source;
    ulong size;

    ubyte[4] pad;
}

__gshared align(16) CopyQueueEntry[256] copyQueue;
__gshared align(16) size_t copyQueueCount;
__gshared align(16) size_t workDoneCount;
__gshared align(16) uint copyQueueLocked;

static immutable string __mmPause = "asm nothrow pure { rep; nop; }";
import core.stdc.stdio;

extern (C) void* copyLoop(void* arg)
{
    import core.stdc.string;
    import core.stdc.stdio;
//    printf("starting copyLoop\n");
    size_t nextCopyItem = 0;
    for(;;)
    {
        assert(copyQueueCount < 192); // we are getting to close the limit
        if (copyQueueCount > 32 && !copyQueueLocked)
        {
            mixin(LockQueue("copyQueueLocked"));

            // not a foreach because the optimizer can't see the limit
            // due to lowering :/
            const ourCopyQueueCount = copyQueueCount;

            //written that way for some smart autovectorizer :)
            for(int i = 0; i < ourCopyQueueCount; i += 4)
            {
                auto e1 = copyQueue[nextCopyItem++];
                auto e2 = copyQueue[nextCopyItem++];
                auto e3 = copyQueue[nextCopyItem++];
                auto e4 = copyQueue[nextCopyItem++];

                memcpy(e1.dest, e1.source, e1.size);
                memcpy(e2.dest, e2.source, e2.size);
                memcpy(e3.dest, e3.source, e3.size);
                memcpy(e4.dest, e4.source, e4.size);

                workDoneCount += 4;
            }
            goto LsmallCopy;

        }
        mixin(__mmPause);
        mixin(readFence);
        if (copyQueueCount && !copyQueueLocked)
        {
            mixin(LockQueue("copyQueueLocked"));
        LsmallCopy:
            for( ; copyQueueCount;)
            {
                auto e1 = copyQueue[nextCopyItem++];
                memcpy(e1.dest, e1.source, e1.size);
                workDoneCount++;
                copyQueueCount--;
            }
        }
        else if (!copyQueueLocked && !copyQueueCount)
        {
            // printf("No work to be done\n");
            Thread.sleep(msecs(100));
        }
    LCopyfinished:
        mixin(writeFence);
        mixin(UnlockQueue("copyQueueLocked"));
        // non critical
        nextCopyItem = 0;
        mixin(__mmPause);
    }
}

void initWorkerThread()
{
    copyQueueLocked = 0;

    pthread_t copyThread;
    pthread_create(&copyThread, null, &copyLoop, null);


}
// enqueueMalloc()
// enqueueRealloc()
// enqueueMangle()
// TOOD  --- PERFORMANCE ----
// Replace LockedQueue by SmarterScheme which uses two rings

/// Assumes that memory at source will valid forever!
static string enqueueCopyString(string dest, string source, string size, string waitHandle = null)
{
    assert(__ctfe);

    string result =
"
do {
    auto entry = CopyQueueEntry(
        " ~ dest ~ ",
        " ~ source ~ ",
        " ~ size ~ "
    );
    if ((!copyQueueLocked) && copyQueueCount < 192) {

        " ~ LockQueue("copyQueueLocked") ~ "
        // when we reach this point the lock has been aquired.
        " ~ (waitHandle !is null ?  waitHandle ~ " = copyQueueCount;" : "") ~ "

        copyQueue[copyQueueCount++] = entry;
        " ~ UnlockQueue("copyQueueLocked") ~ "
    }
    else { 
        " ~ __mmPause ~ "
        continue; }
} while (0);
";

  return result;
}

void main()
{
    assert(!copyQueueLocked);
    printf("GetThreadId: %d\n", GetThreadId());
    initWorkerThread();
    uint owner;
    printf("copyQueueLocked: %d\n", copyQueueLocked);
    mixin(LockQueue("copyQueueLocked", "owner"));
    // we've got the lock which means we're the owner
    printf("My thread Id:%d\n", owner);
    mixin(UnlockQueue("copyQueueLocked"));
    long source = 22;
    long dest = 0;
    size_t wait_handle;
    mixin(enqueueCopyString("&dest", "&source", "ulong.sizeof", "wait_handle"));
    while (workDoneCount <= wait_handle)
    {
        mixin(__mmPause);
    }
    assert(dest == source);
}
