/*******************************************************************************
  copyright:   Copyright (c) 2006 Juan Jose Comellas. All rights reserved
  license:     BSD style: $(LICENSE)
  author:      Juan Jose Comellas <juanjo@comellas.com.ar>
*******************************************************************************/

private import tango.util.locks.ReadWriteMutex;
private import tango.util.locks.Mutex;
private import tango.core.Thread;
private import tango.text.convert.Integer;
debug (readwritemutex)
{
    private import tango.util.log.Log;
    private import tango.util.log.ConsoleAppender;
    private import tango.util.log.DateLayout;
}


/**
 * Example program for the tango.util.locks.ReadWriteMutex module.
 */
void main(char[][] args)
{
    const uint ReaderThreads    = 100;
    const uint WriterThreads    = 20;
    const uint LoopsPerReader   = 10000;
    const uint LoopsPerWriter   = 1000;
    const uint CounterIncrement = 3;

    debug (readwritemutex)
    {
        scope Logger log = Log.getLogger("rwmutex");

        log.addAppender(new ConsoleAppender(new DateLayout()));

        log.info("ReadWriteMutex test");
    }

    ReadWriteMutex  rwlock = new ReadWriteMutex();
    Mutex           mutex = new Mutex();
    uint            readCount = 0;
    uint            passed = 0;
    uint            failed = 0;

    void mutexReaderThread()
    {
        debug (readwritemutex)
        {
            Logger log = Log.getLogger("rwmutex." ~ Thread.getThis().name());

            log.trace("Starting reader thread");
        }

        for (uint i = 0; i < LoopsPerReader; ++i)
        {
            // All the reader threads acquire the mutex for reading and when they are
            // all done
            rwlock.acquireRead();

            for (uint j = 0; j < CounterIncrement; ++j)
            {
                mutex.acquire();
                ++readCount;
                mutex.release();
            }

            rwlock.release();
        }
    }

    void mutexWriterThread()
    {
        debug (readwritemutex)
        {
            Logger log = Log.getLogger("rwmutex." ~ Thread.getThis().name());

            log.trace("Starting writer thread");
        }

        for (uint i = 0; i < LoopsPerWriter; ++i)
        {
            rwlock.acquireWrite();

            mutex.acquire();
            if (readCount % 3 == 0)
            {
                ++passed;
            }
            mutex.release();

            rwlock.release();
        }
    }

    ThreadGroup group = new ThreadGroup();
    Thread      thread;
    char[10]    tmp;

    for (uint i = 0; i < ReaderThreads; ++i)
    {
        thread = new Thread(&mutexReaderThread);
        thread.name = "reader-" ~ format(tmp, i);

        debug (readwritemutex)
            log.trace("Created reader thread " ~ thread.name);
        thread.start();

        group.add(thread);
    }

    for (uint i = 0; i < WriterThreads; ++i)
    {
        thread = new Thread(&mutexWriterThread);
        thread.name = "writer-" ~ format(tmp, i);

        debug (readwritemutex)
            log.trace("Created writer thread " ~ thread.name);
        thread.start();

        group.add(thread);
    }

    debug (readwritemutex)
        log.trace("Waiting for threads to finish");
    group.joinAll();

    if (passed == WriterThreads * LoopsPerWriter)
    {
        debug (readwritemutex)
            log.info("The ReadWriteMutex test was successful");
    }
    else
    {
        debug (readwritemutex)
        {
            log.error("The ReadWriteMutex is not working properly: the counter has an incorrect value");
            assert(false);
        }
        else
        {
            assert(false, "The ReadWriteMutex is not working properly: the counter has an incorrect value");
        }
    }
}
