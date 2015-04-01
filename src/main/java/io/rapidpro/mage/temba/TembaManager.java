package io.rapidpro.mage.temba;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.process.BaseProcess;
import io.rapidpro.mage.util.JsonUtils;
import io.dropwizard.lifecycle.Managed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.ws.rs.core.Response;

/**
 * Manager for Temba functionality
 */
public class TembaManager implements Managed {

    protected static final Logger log = LoggerFactory.getLogger(TembaManager.class);

    private final Cache m_cache;

    private final RequestProcess m_process;

    private int[] RETRY_STATUSES = { 502, 503, 504 };  // response statuses which should trigger a delayed retry

    public TembaManager(Cache cache, String apiUrl, String authKey, boolean production) {
        m_cache = cache;

        m_process = new RequestProcess(apiUrl, authKey, production);
    }
    /**
     * @see io.dropwizard.lifecycle.Managed#start()
     */
    @Override
    public void start() throws Exception {
        m_process.start();
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#stop()
     */
    @Override
    public void stop() throws Exception {
        m_process.stop();
    }

    /**
     * Queues a request to the Temba API
     * @param request the request
     */
    public void queueRequest(TembaRequest request) {
        m_cache.listRPush(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE, JsonUtils.encode(request, true));
    }

    /**
     * Background process to make remote API requests
     */
    protected class RequestProcess extends BaseProcess {

        protected final long[] m_retryDelays = { 1000l, 5000l, 30000l };

        protected TembaClients.Client m_client;
        protected int m_retryCount = 0;

        public RequestProcess(String apiUrl, String authKey, boolean production) {
            super("tembarequests", 1000l);

            m_client = TembaClients.getClient(apiUrl, authKey, production);
        }

        /**
         * @see io.rapidpro.mage.process.BaseProcess#doUnitOfWork()
         */
        @Override
        protected long doUnitOfWork() {
            String encoded = m_cache.listLPop(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE);
            if (encoded == null) {
                log.debug("Found no pending Temba requests");
                return 1000l; // look again after 1 second
            }

            TembaRequest request = JsonUtils.parse(encoded, TembaRequest.class);
            Response response = m_client.call(request);

            if (shouldRetry(response)) {
                // put back at start of list and schedule retry
                m_cache.listLPush(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE, encoded);

                m_retryCount++;
                long delay = m_retryDelays[Math.min(m_retryCount, m_retryDelays.length) - 1];

                log.warn("Temba API request failed with status " + response.getStatus() + ", retrying in " + delay + " milliseconds");
                return delay;
            }
            else {
                m_retryCount = 0;
                return 0l;
            }
        }
    }

    /**
     * Determines whether a request should be retried
     * @param response the request response
     * @return true if request should be retried
     */
    protected boolean shouldRetry(Response response) {
        for (int retryStatus : RETRY_STATUSES) {
            if (retryStatus == response.getStatus()) {
                return true;
            }
        }
        return false;
    }
}
