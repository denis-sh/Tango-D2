/*******************************************************************************
  copyright:   Copyright (c) 2006 Juan Jose Comellas. All rights reserved
  license:     BSD style: $(LICENSE)
  author:      Juan Jose Comellas <juanjo@comellas.com.ar>
*******************************************************************************/

module tango.util.locks.ReadWriteMutex;

public import tango.core.Type;

private import tango.util.locks.LockException;
private import tango.text.convert.Integer;


version (Posix)
{
    private import tango.util.locks.Mutex;
    private import tango.sys.Common;

    private import tango.stdc.posix.pthread;
    private import tango.stdc.errno;

    /**
     * Wrapper for readers/writer locks.
     * This class is particularly useful for applications that have many more
     * concurrent readers than writers.
     */
    public class ReadWriteMutex
    {
        extern (C)
        {
            private alias int function(pthread_rwlock_t*) PthreadLock;
            private alias int function(pthread_rwlock_t*, timespec*) PthreadTimedLock;
        }

        public alias acquireWrite      acquire;
        public alias tryAcquireWrite   tryAcquire;

        private pthread_rwlock_t _lock;

        /**
         * Initialize a readers/writer lock.
         */
        public this()
        {
            pthread_rwlockattr_t attr;

            pthread_rwlockattr_init(&attr);
            // pthread_rwlockattr_setpshared(&attr, PTHREAD_PROCESS_PRIVATE);

            int rc = pthread_rwlock_init(&_lock, &attr);
            if (rc != 0)
            {
                checkError(rc, __FILE__, __LINE__);
            }
        }

        /**
         * Implicitly destroy a readers/writer lock.
         */
        public ~this()
        {
            int rc = pthread_rwlock_destroy(&_lock);
            if (rc != 0)
            {
                checkError(rc, __FILE__, __LINE__);
            }
        }

        /**
         * Acquire a read lock, but block if a writer holds the lock.
         */
        public void acquireRead()
        {
            int rc = pthread_rwlock_rdlock(&_lock);
            if (rc != 0)
            {
                checkError(rc, __FILE__, __LINE__);
            }
        }

        /**
         * Acquire a write lock, but block if any readers or a writer hold
         * the lock.
         */
        public void acquireWrite()
        {
            int rc = pthread_rwlock_wrlock(&_lock);
            if (rc != 0)
            {
                checkError(rc, __FILE__, __LINE__);
            }
        }

        /**
         * Conditionally acquire a read lock (i.e., won't block).
         *
         * Returns:
         * true if the lock was acquired; false if not (because a writer
         * already had the lock).
         */
        public bool tryAcquireRead()
        {
            return tryAcquireHelper(&pthread_rwlock_tryrdlock);
        }

        /**
         * Conditionally acquire a write lock (i.e., won't block).
         *
         * Returns:
         * true if the lock was acquired; false if not (because another
         * writer already had the lock).
         */
        public bool tryAcquireWrite()
        {
            return tryAcquireHelper(&pthread_rwlock_trywrlock);
        }

        /**
         * Conditionally upgrade a read lock to a write lock. This only works
         * if there are no other readers present, in which case the method
         * returns true. Otherwise, the method returns false.
         *
         * Remarks:
         * Note that the caller of this method *must* already possess this
         * lock as a read lock (but this condition is not checked by the
         * current implementation).
         */
        public bool tryAcquireWriteUpgrade()
        {
            // To upgrade a read lock to a write lock on POSIX platforms you
            // just need to lock for writing with the read lock held.
            return tryAcquireHelper(&pthread_rwlock_trywrlock);
        }

        /**
         * Conditionally try to acquire a read lock for a specified amount
         * of time (i.e. it will only block until the $(D_PARAM timeout) is
         * reached).
         *
         * Returns:
         * true if the lock was acquired; false if not (because a writer
         * already had the lock).
         */
        public bool tryAcquireRead(Interval timeout)
        {
            return tryAcquireTimedHelper(&pthread_rwlock_timedrdlock, timeout);
        }

        /**
         * Conditionally try to acquire a write lock for a specified amount
         * of time (i.e. it will only block until the $(D_PARAM timeout) is
         * reached).
         *
         * Returns:
         * true if the lock was acquired; false if not (because another
         * writer already had the lock).
         */
        public bool tryAcquireWrite(Interval timeout)
        {
            return tryAcquireTimedHelper(&pthread_rwlock_timedwrlock, timeout);
        }

        /**
         * Unlock a readers/writer lock.
         */
        public void release()
        {
            int rc = pthread_rwlock_unlock(&_lock);
            if (rc != 0)
            {
                checkError(rc, __FILE__, __LINE__);
            }
        }

        /**
         * Helper method that conditionally acquires a reader or writer lock
         * depending on the function it receives as argument.
         */
        private final bool tryAcquireHelper(PthreadLock fp)
        {
            int rc = fp(&_lock);
            if (rc != 0)
            {
                return true;
            }
            else if (rc == EBUSY)
            {
                return false;
            }
            else
            {
                checkError(rc, __FILE__, __LINE__);
                return false;
            }
        }

        /**
         * Helper method that conditionally tries to acquire a reader or
         * writer lock for a specified amount of time, depending on the
         * function it receives as argument.
         */
        private final bool tryAcquireTimedHelper(PthreadTimedLock fp, Interval timeout)
        {
            timespec ts;

            int rc = fp(&_lock, toTimespec(&ts, toAbsoluteTime(timeout)));
            if (rc != 0)
            {
                return true;
            }
            else if (rc == ETIMEDOUT)
            {
                return false;
            }
            else
            {
                checkError(rc, __FILE__, __LINE__);
                return false;
            }
        }

        /**
         * Check the $(D_PARAM errorCode) argument against possible values
         * of SysError.lastCode() and throw an exception with the description
         * of the error.
         *
         * Params:
         * errorCode    = SysError.lastCode() value; must not be 0.
         * file         = name of the source file where the check is being
         *                made; you would normally use __FILE__ for this
         *                parameter.
         * line         = line number of the source file where this method
         *                was called; you would normally use __LINE__ for
         *                this parameter.
         *
         * Throws:
         * AlreadyLockedException when the mutex has already been locked by
         * another thread; DeadlockException when the mutex has already
         * been locked by the calling thread; InvalidMutexException when the
         * mutex has not been properly initialized; MutexOwnerException when
         * the calling thread does not own the mutex; LockException for any
         * of the other cases in which $(D_PARAM errorCode) is not 0.
         */
        protected final void checkError(uint errorCode, char[] file, uint line)
        in
        {
            assert(errorCode != 0, "checkError() was called with errorCode == 0");
        }
        body
        {
            switch (errorCode)
            {
                case EBUSY:
                    throw new AlreadyLockedException(file, line);
                    // break;
                case EDEADLK:
                    throw new DeadlockException(file, line);
                    // break;
                case EAGAIN:
                    throw new OutOfLocksException(file, line);
                    // break;
                case EINVAL:
                    throw new InvalidMutexException(file, line);
                    // break;
                case EPERM:
                    throw new MutexOwnerException(file, line);
                    // break;
                default:
                    char[10] tmp;

                    throw new LockException("Unknown mutex error " ~ format(tmp, errorCode) ~
                                            ": " ~ SysError.lookup(errorCode), file, line);
                    // break;
            }
        }
    }
}
else version (Windows)
{
    private import tango.util.locks.Mutex;
    private import tango.util.locks.Condition;


    /**
     * Wrapper for readers/writer locks.
     * This class is particularly useful for applications that have many more
     * concurrent readers than writers.
     *
     * Remarks:
     * Based on the ACE_RW_Mutex class from the
     * $(LINK2 http://www.cs.wustl.edu/~schmidt/ACE.html, ACE framework).
     */
    public class ReadWriteMutex
    {
        /** Serialize access to internal state. */
        private Mutex _lock;
        /** Reader threads waiting to acquire the lock. */
        private Condition _waitingReaders;
        /** Number of waiting readers. */
        private int _waitingReadersCount = 0;
        /** Writer threads waiting to acquire the lock. */
        private Condition _waitingWriters;
        /** Number of waiting writers. */
        private int _waitingWritersCount = 0;
        /**
         * Value is -1 if writer has the lock, else this keeps track of the
         * number of readers holding the lock.
         */
        private int _refCount = 0;
        /** Indicate that a reader is trying to upgrade */
        bool _isImportantWriter = false;
        /** Condition for the upgrading reader */
        Condition _waitingImportantWriter;

        /**
         * Initialize a readers/writer lock.
         */
        public this()
        {
            _lock = new Mutex();
            scope(failure)
                delete _lock;

            _waitingReaders = new Condition(_lock);
            scope(failure)
                delete _waitingReaders;

            _waitingWriters = new Condition(_lock);
            scope(failure)
                delete _waitingWriters;

            _waitingImportantWriter = new Condition(_lock);
        }

        /**
         * Implicitly destroy a readers/writer lock.
         */
        public ~this()
        {
            delete _waitingImportantWriter;
            delete _waitingWriters;
            delete _waitingReaders;
            delete _lock;
        }

        /**
         * Acquire a read lock, but block if a writer holds the lock.
         */
        public void acquireRead()
        {
            _lock.acquire();
            scope(exit)
                _lock.release();

            // Give preference to writers who are waiting.
            while (_refCount < 0 || _waitingWritersCount > 0)
            {
                _waitingReadersCount++;
                try
                {
                    _waitingReaders.wait();
                }
                finally
                {
                    _waitingReadersCount--;
                }
            }
            _refCount++;
        }

        /**
         * Acquire a write lock, but block if any readers or a writer hold
         * the lock.
         */
        public void acquireWrite()
        {
            _lock.acquire();
            scope(exit)
                _lock.release();

            while (_refCount != 0)
            {
                _waitingWritersCount++;
                try
                {
                    _waitingWriters.wait();
                }
                finally
                {
                    _waitingWritersCount--;
                }
            }

            _refCount = -1;
        }

        /**
         * Conditionally acquire a read lock (i.e., won't block).
         *
         * Returns:
         * true if the lock was acquired; false if not (because a writer
         * already had the lock).
         */
        public bool tryAcquireRead()
        {
            bool success = false;

            _lock.acquire();
            scope(exit)
                _lock.release();

            if (_refCount != -1 && _waitingWritersCount <= 0)
            {
                _refCount++;
                success = true;
            }
            return success;
        }

        /**
         * Conditionally acquire a write lock (i.e., won't block).
         *
         * Returns:
         * true if the lock was acquired; false if not (because another
         * writer already had the lock).
         */
        public bool tryAcquireWrite()
        {
            bool success = false;

            _lock.acquire();
            scope(exit)
                _lock.release();

            if (_refCount == 0)
            {
                _refCount = -1;
                success = true;
            }
            return success;
        }

        /**
         * Conditionally upgrade a read lock to a write lock. This only works
         * if there are no other readers present, in which case the method
         * returns true. Otherwise, the method returns false.
         *
         * Remarks:
         * Note that the caller of this method *must* already possess this
         * lock as a read lock (but this condition is not checked by the
         * current implementation).
         */
        public bool tryAcquireWriteUpgrade()
        {
            bool success = true;

            _lock.acquire();
            scope(exit)
                _lock.release();

            // Check that another reader is not already upgrading
            if (!_isImportantWriter)
            {
                // Wait until only I am left
                while (_refCount > 1)
                {
                    // Prohibit any more readers
                    ++_waitingWritersCount;
                    _isImportantWriter = true;

                    try
                    {
                        _waitingImportantWriter.wait();
                    }
                    finally
                    {
                        _isImportantWriter = false;
                        --_waitingWritersCount;
                    }
                }

                // Now I am the writer
                _refCount = -1;
            }
            return success;
        }

        /**
         * Conditionally try to acquire a read lock for a specified amount
         * of time (i.e. it will only block until the $(D_PARAM timeout) is
         * reached).
         *
         * Returns:
         * true if the lock was acquired; false if not (because a writer
         * already had the lock).
         */
        public bool tryAcquireRead(Interval timeout)
        {
            bool success = false;

            _lock.acquire();
            scope(exit)
                _lock.release();

            // Give preference to writers who are waiting.
            while (_refCount < 0 || _waitingWritersCount > 0)
            {
                _waitingReadersCount++;
                try
                {
                    success = _waitingReaders.wait(timeout);
                }
                finally
                {
                    _waitingReadersCount--;
                }
            }
            _refCount++;

            return success;
        }

        /**
         * Conditionally try to acquire a write lock for a specified amount
         * of time (i.e. it will only block until the $(D_PARAM timeout) is
         * reached).
         *
         * Returns:
         * true if the lock was acquired; false if not (because another
         * writer already had the lock).
         */
        public bool tryAcquireWrite(Interval timeout)
        {
            bool success = false;

            _lock.acquire();
            scope(exit)
                _lock.release();

            while (_refCount != 0)
            {
                ++_waitingWritersCount;
                try
                {
                    success = _waitingWriters.wait(timeout);
                }
                finally
                {
                    --_waitingWritersCount;
                }
            }

            _refCount = -1;

            return success;
        }

        /**
         * Release a readers/writer lock.
         */
        public void release()
        {
            _lock.acquire();
            scope(exit)
                _lock.release();

            if (_refCount != 0)
            {
                if (_refCount > 0)
                {
                    // Releasing a reader
                    --_refCount;
                }
                else // if (_refCount == -1)
                {
                    // Releasing the writer
                    _refCount = 0;
                }

                if (_isImportantWriter && _refCount == 1)
                {
                    // Only the reader requesting to upgrade its lock is left over.
                    _waitingImportantWriter.notify();
                }
                else if (_waitingWritersCount > 0 && _refCount == 0)
                {
                    // Give preference to writers over readers...
                    _waitingWriters.notify();
                }
                else if (_waitingReadersCount > 0 && _waitingWritersCount == 0)
                {
                    _waitingReaders.notifyAll();
                }
            }
        }
    }
}
else
{
    static assert(false, "Read-write locks are not supported on this platform");
}


/**
 * Exception-safe locking mechanism that wraps a ReadWriteMutex and acquires
 * it for reading.
 *
 * This class is meant to be used within a method or function (or any other
 * block that defines a scope). It performs automatic aquisition and release
 * of a synchronization object.
 *
 * Examples:
 * ---
 * void method1(ReadWriteMutex mutex)
 * {
 *     ScopedReadLock lock(mutex);
 *
 *     if (!doSomethingProtectedByMutex())
 *     {
 *         // As the ScopedReadLock is an scope class, it will be destroyed when
 *         // method1() goes out of scope and inside its destructor it will
 *         // release the ReadWriteMutex.
 *         throw Exception("The mutex will be released when method1() returns");
 *     }
 * }
 */
public scope class ScopedReadLock
{
    private ReadWriteMutex _mutex;
    private bool _acquired;

    /**
     * Initialize the lock, optionally acquiring the mutex for reading.
     *
     * Params:
     * mutex            = ReadWriteMutex that will be acquired on construction
     *                    of an instance of this class and released upon its
     *                    destruction.
     * acquireInitially = indicates whether the ReadWriteMutex should be
     *                    acquired inside this method or not.
     *
     * Remarks:
     * The pattern implemented by this class is also sometimes called guard.
     */
    public this(ReadWriteMutex mutex, bool acquireInitially = true)
    {
        _mutex = mutex;
        if (acquireInitially)
        {
            _mutex.acquireRead();
        }
        _acquired = acquireInitially;
    }

    /**
     * Release the underlying ReadWriteMutex (it if had been acquired and not
     * previously released) and destroy the scoped lock.
     */
    public ~this()
    {
        release();
    }

    /**
     * Acquire the underlying mutex for reading.
     *
     * Remarks:
     * If the mutex had been previously acquired through this class this
     * method doesn't do anything.
     */
    public final void acquire()
    {
        if (!_acquired)
        {
            _mutex.acquireRead();
            _acquired = true;
        }
    }

    /**
     * Release the underlying mutex.
     *
     * Remarks:
     * If the mutex had not been previously acquired through this class this
     * method doesn't do anything.
     */
    public final void release()
    {
        if (_acquired)
        {
            _mutex.release();
            _acquired = false;
        }
    }
}


/**
 * Exception-safe locking mechanism that wraps a ReadWriteMutex and acquires
 * it for writing.
 *
 * This class is meant to be used within a method or function (or any other
 * block that defines a scope). It performs automatic aquisition and release
 * of a synchronization object.
 *
 * Examples:
 * ---
 * void method1(ReadWriteMutex mutex)
 * {
 *     ScopedWriteLock lock(mutex);
 *
 *     if (!doSomethingProtectedByMutex())
 *     {
 *         // As the ScopedWriteLock is an scope class, it will be destroyed when
 *         // method1() goes out of scope and inside its destructor it will
 *         // release the ReadWriteMutex.
 *         throw Exception("The mutex will be released when method1() returns");
 *     }
 * }
 */
public scope class ScopedWriteLock
{
    private ReadWriteMutex _mutex;
    private bool _acquired;

    /**
     * Initialize the lock, optionally acquiring the mutex for writing.
     *
     * Params:
     * mutex            = ReadWriteMutex that will be acquired on construction
     *                    of an instance of this class and released upon its
     *                    destruction.
     * acquireInitially = indicates whether the ReadWriteMutex should be
     *                    acquired inside this method or not.
     *
     * Remarks:
     * The pattern implemented by this class is also sometimes called guard.
     */
    public this(ReadWriteMutex mutex, bool acquireInitially = true)
    {
        _mutex = mutex;
        _mutex.acquireWrite();
        _acquired = true;
    }

    /**
     * Release the underlying ReadWriteMutex (it if had been acquired and not
     * previously released) and destroy the scoped lock.
     */
    public ~this()
    {
        release();
    }

    /**
     * Acquire the underlying mutex for writing.
     *
     * Remarks:
     * If the mutex had been previously acquired through this class this
     * method doesn't do anything.
     */
    public final void acquire()
    {
        if (!_acquired)
        {
            _mutex.acquireWrite();
            _acquired = true;
        }
    }

    /**
     * Release the underlying mutex.
     *
     * Remarks:
     * If the mutex had not been previously acquired through this class this
     * method doesn't do anything.
     */
    public final void release()
    {
        if (_acquired)
        {
            _mutex.release();
            _acquired = false;
        }
    }
}


debug (UnitTest)
{
    private import tango.util.locks.Mutex;
    private import tango.core.Thread;
    private import tango.text.convert.Integer;
    debug (readwritemutex)
    {
        private import tango.util.log.Log;
        private import tango.util.log.ConsoleAppender;
        private import tango.util.log.DateLayout;
    }

    unittest
    {
        const uint ReaderThreads    = 100;
        const uint WriterThreads    = 20;
        const uint LoopsPerReader   = 10000;
        const uint LoopsPerWriter   = 1000;
        const uint CounterIncrement = 3;

        debug (readwritemutex)
        {
            scope Logger log = Log.getLogger("readwritemutex");

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
                Logger log = Log.getLogger("readwritemutex." ~ Thread.getThis().name());

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
                Logger log = Log.getLogger("readwritemutex." ~ Thread.getThis().name());

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
}
