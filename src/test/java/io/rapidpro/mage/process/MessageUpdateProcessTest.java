package io.rapidpro.mage.process;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.test.TestUtils;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

import java.util.Date;
import java.util.Map;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.process.MessageUpdateProcess}
 */
public class MessageUpdateProcessTest extends BaseServicesTest {

    private final MessageUpdateProcess m_job = new MessageUpdateProcess(getServices(), getCache());

    /**
     * @see MessageUpdateProcess#doUnitOfWork()
     */
    @Test
    public void doUnitOfWork_shouldDoNothingWhenQueueEmpty() throws Exception {
        m_job.doUnitOfWork();
    }

    /**
     * @see MessageUpdateProcess#doUnitOfWork()
     */
    @Test
    public void doUnitOfWork_shouldUpdateStatuses() throws Exception {
        Date date1 = TestUtils.date(2014, 1, 1);
        Date date2 = TestUtils.date(2014, 1, 2);
        Date date3 = TestUtils.date(2014, 1, 3);
        MessageUpdate update1 = new MessageUpdate(-81, Status.SENT, date1, -71);
        MessageUpdate update2 = new MessageUpdate(-82, Status.DELIVERED, date2, -71);
        MessageUpdate update3 = new MessageUpdate(-83, Status.FAILED, date3, -71);

        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update1, true));
        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update2, true));
        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update3, true));

        m_job.doUnitOfWork();

        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, -81);
        assertThat(message1.get("status"), is("S"));
        assertThat(message1.get("sent_on"), is(date1));
        assertThat(message1.get("modified_on"), nullValue());

        Map<String, Object> message2 = fetchSingleById(Table.MESSAGE, -82);
        assertThat(message2.get("status"), is("D"));
        assertThat(message2.get("sent_on"), is(TestUtils.date("2014-01-22 23:26:02.181")));
        assertThat(message2.get("modified_on"), is(date2));

        Map<String, Object> message3 = fetchSingleById(Table.MESSAGE, -83);
        assertThat(message3.get("status"), is("F"));

        Map<String, Object> broadcast1 = fetchSingleById(Table.BROADCAST, -71);
        assertThat(broadcast1.get("status"), is("S"));
    }

    /**
     * @see MessageUpdateProcess#doUnitOfWork()
     */
    @Test
    public void doUnitOfWork_shouldOnlyUpdateWiredToSent() throws Exception {
        Date date1 = TestUtils.date(2014, 1, 1);
        Date date2 = TestUtils.date(2014, 1, 2);
        MessageUpdate update1 = new MessageUpdate(-81, Status.SENT, date1, -71);
        MessageUpdate update2 = new MessageUpdate(-82, Status.SENT, date2, -71);

        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update1, true));
        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update2, true));

        m_job.doUnitOfWork();

        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, -81);
        assertThat(message1.get("status"), is("S"));
        assertThat(message1.get("sent_on"), is(date1));

        Map<String, Object> message2 = fetchSingleById(Table.MESSAGE, -82);
        assertThat(message2.get("status"), is("S"));
        assertThat(message2.get("sent_on"), is(TestUtils.date("2014-01-22 23:26:02.181"))); // unchanged

        Map<String, Object> message3 = fetchSingleById(Table.MESSAGE, -83);
        assertThat(message3.get("status"), is("D")); // unchanged
        assertThat(message3.get("sent_on"), is(TestUtils.date("2014-01-22 23:27:02.181"))); // unchanged

        Map<String, Object> broadcast1 = fetchSingleById(Table.BROADCAST, -71);
        assertThat(broadcast1.get("status"), is("S"));
    }

    /**
     * @see MessageUpdateProcess#doUnitOfWork()
     */
    @Test
    public void doUnitOfWork_shouldIgnoreDuplicateUpdates() throws Exception {
        // should consider equal even if dates are different
        MessageUpdate update1 = new MessageUpdate(-81, Status.SENT, TestUtils.date(2014, 1, 1), -71);
        MessageUpdate update2 = new MessageUpdate(-81, Status.SENT, TestUtils.date(2014, 1, 2), -71);

        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update1, true));
        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(update2, true));

        m_job.doUnitOfWork();

        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, -81);
        assertThat(message1.get("status"), is("S"));
        assertThat(message1.get("sent_on"), is(TestUtils.date(2014, 1, 1))); // update #1 was performed
    }
}