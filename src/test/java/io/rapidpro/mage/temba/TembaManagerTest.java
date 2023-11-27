package io.rapidpro.mage.temba;

import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.test.TestUtils;
import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.temba.request.HandleMessageRequest;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

/**
 * Tests for {@link io.rapidpro.mage.temba.TembaManager}
 */
public class TembaManagerTest extends BaseServicesTest {

    @Test
    public void queueRequest() throws Exception {
        TembaRequest request1 = new HandleMessageRequest(123, true);
        getCache().listRPush(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE, JsonUtils.encode(request1, true));

        // wait for list to become empty
        TestUtils.assertBecomesTrue(() -> getCache().listLength(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE) == 0, 10_000);

        // TODO figure out how best to inject a new cache implementation like below to test redis failures
    }

    /**
     * Cache sub class which blows up on first operation but works for subsequent calls
     */
    protected class FailInitiallyCache extends Cache {
        private boolean m_initial = true;

        public FailInitiallyCache(String host, int database, String password) {
            super(host, database, password);
        }

        @Override
        public <T> T perform(OperationWithResource<T> operation) {
            if (m_initial) {
                m_initial = false;
                throw new RuntimeException("Arrgghhh");
            }

            return super.perform(operation);
        }
    }
}
