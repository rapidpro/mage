package io.rapidpro.mage.process;

import com.google.common.util.concurrent.ThreadFactoryBuilder;
import io.dropwizard.lifecycle.Managed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

/**
 * Base class for background processes made of tasks which return a dynamic delay value.
 */
public abstract class BaseProcess implements Managed {

    protected final Logger log = LoggerFactory.getLogger(getClass());

    protected static final long DELAY_ON_EXCEPTION = 30_000;

    private final String m_name;

    private final long m_initialDelay;

    private ScheduledExecutorService m_scheduler;

    protected BaseProcess(String name, long initialDelay) {
        this.m_name = name;
        this.m_initialDelay = initialDelay;
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#start()
     */
    @Override
    public void start() throws Exception {
        ThreadFactory tf = new ThreadFactoryBuilder().setNameFormat(m_name + "-%d").build();
        m_scheduler = Executors.newSingleThreadScheduledExecutor(tf);

        m_scheduler.schedule(new UnitOfWorkWrapper(), m_initialDelay, TimeUnit.MILLISECONDS);
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#stop()
     */
    @Override
    public void stop() throws Exception {
        m_scheduler.shutdown();

        try {
            if (!m_scheduler.awaitTermination(5, TimeUnit.SECONDS)) {
                m_scheduler.shutdownNow();

                if (!m_scheduler.awaitTermination(5, TimeUnit.SECONDS)) {
                    log.error("Process did not terminate cleanly");
                }
            }
        } catch (InterruptedException ie) {
            m_scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Runnable which invokes the subclass doUnitOfWork() and reschedules based on returned delay value. Also makes sure
     * that all exceptions are logged and don't prevent rescheduling.
     */
    protected class UnitOfWorkWrapper implements Runnable {
        /**
         * @see Runnable#run()
         */
        @Override
        public void run() {
            long delay;
            try {
                delay = doUnitOfWork();
            }
            catch (Exception e) {
                log.error("Error in process " + m_name, e);
                delay = DELAY_ON_EXCEPTION;
            }

            m_scheduler.schedule(new UnitOfWorkWrapper(), delay, TimeUnit.MILLISECONDS);
        }
    }

    /**
     * Perform a unit of work
     * @return the delay before next call in milliseconds
     */
    protected abstract long doUnitOfWork();
}