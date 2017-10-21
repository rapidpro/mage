package io.rapidpro.mage.dao;

import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.Direction;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.test.TestUtils;
import org.junit.Test;

import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.dao.MessageDao}
 */
public class MessageDaoTest extends BaseServicesTest {

    private MessageDao m_dao = getServices().getMessageService().getDao();

    /**
     * @see MessageDao#getIncomingContextByChannelAddressAndType(io.rapidpro.mage.core.ChannelType, String)
     */
    @Test
    public void getIncomingContextByChannelAddressAndType() {
        IncomingContext context = m_dao.getIncomingContextByChannelAddressAndType(ChannelType.TWILIO, "+250111111111");
        assertThat(context.getChannelId(), is(-41));
        assertThat(context.getChannelCountry(), is("RW"));
        assertThat(context.getOrgId(), is(-11));
        assertThat(context.getOrgConfig().get("ACCOUNT_SID").textValue(), is("ACe0da56e18798f1bdd9569def026e2ee7"));
        assertThat(context.getOrgConfig().get("ACCOUNT_TOKEN").textValue(), is("6abb5cfa9f8b9018516cb6159088ef8d"));

        // check non-existent number
        assertThat(m_dao.getIncomingContextByChannelAddressAndType(ChannelType.TWILIO, "+0000000"), nullValue());
    }

    /**
     * @see MessageDao#getIncomingContextByChannelUuidAndType(String, io.rapidpro.mage.core.ChannelType)
     */
    @Test
    public void getIncomingContextByChannelUuidAndType() {
        IncomingContext context = m_dao.getIncomingContextByChannelUuidAndType("788B08AF-405C-43EF-9D40-7535CFA7663E", ChannelType.EXTERNAL);
        assertThat(context.getChannelId(), is(-43));
        assertThat(context.getChannelCountry(), is("RW"));
        assertThat(context.getOrgId(), is(-11));
        assertThat(context.getOrgConfig().get("ACCOUNT_SID").textValue(), is("ACe0da56e18798f1bdd9569def026e2ee7"));
        assertThat(context.getOrgConfig().get("ACCOUNT_TOKEN").textValue(), is("6abb5cfa9f8b9018516cb6159088ef8d"));

        // check non-existent channel UUID
        assertThat(m_dao.getIncomingContextByChannelUuidAndType("xxxxxx", ChannelType.EXTERNAL), nullValue());
    }

    /**
     * @see MessageDao#getMessage(String, java.util.Date, int, io.rapidpro.mage.core.Direction)
     */
    @Test
    public void getMessage() {
        assertThat(m_dao.getMessage("Testing", TestUtils.date("2014-01-22 23:25:01.836"), -51, Direction.OUTGOING), is(-81));
        assertThat(m_dao.getMessage("xxx", new Date(), 1, Direction.INCOMING), nullValue());
    }

    /**
     * @see MessageDao#getLastExternalId(int, io.rapidpro.mage.core.Direction)
     */
    @Test
    public void getLastExternalId() {
        assertThat(m_dao.getLastExternalId(-45, Direction.INCOMING), is("SMS86"));
        assertThat(m_dao.getLastExternalId(-46, Direction.INCOMING), nullValue());
    }

    /**
     * @see MessageDao#insertIncoming(Integer, Integer, Integer, String, Integer, java.util.Date, java.util.Date, String)
     */
    @Test
    public void insertIncoming() throws Exception {
        Date createdOn = new Date();
        Date queuedOn = new Date();

        int messageId = m_dao.insertIncoming(-41, -51, -61, "Testing", -11, createdOn, queuedOn, "SMS123");
        assertThat(messageId, greaterThan(0));

        Map<String, Object> message = fetchSingleById(Table.MESSAGE, messageId);
        assertThat(message, hasEntry("channel_id", -41));
        assertThat(message, hasEntry("contact_id", -51));
        assertThat(message, hasEntry("text", "Testing"));
        assertThat(message, hasEntry("direction", "I"));
        assertThat(message, hasEntry("status", "P"));
        assertThat(message, hasEntry("org_id", -11));
        assertThat(message, hasEntry("created_on", createdOn));
        assertThat(message, hasEntry("queued_on", queuedOn));
        assertThat(message, hasEntry("external_id", "SMS123"));
        assertThat(message, hasEntry("topup_id", null));
    }

    /**
     * @see MessageDao#updateBatchToSent(Iterable, Iterable)
     */
    @Test
    public void updateBatchToSent_shouldUpdateAllWiredMessages() throws Exception {
        Date d1 = TestUtils.date(2012, 1, 1);
        Date d2 = TestUtils.date(2012, 1, 2);
        Date d3 = TestUtils.date(2012, 1, 3);
        m_dao.updateBatchToSent(Arrays.asList(-81, -82, -83), Arrays.asList(d1, d2, d3));

        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, -81);
        assertThat(message1, hasEntry("status", "S"));
        assertThat(message1, hasEntry("sent_on", d1));
        Map<String, Object> message2 = fetchSingleById(Table.MESSAGE, -82);
        assertThat(message2, hasEntry("status", "S"));
        assertThat(message2, hasEntry("sent_on", TestUtils.date("2014-01-22 23:26:02.181"))); // unchanged
        Map<String, Object> message3 = fetchSingleById(Table.MESSAGE, -83);
        assertThat(message3, hasEntry("status", "D")); // unchanged from delivered
        assertThat(message3, hasEntry("sent_on", TestUtils.date("2014-01-22 23:27:02.181"))); // unchanged
    }

    /**
     * @see MessageDao#updateBatchToDelivered(Iterable, Iterable)
     */
    @Test
    public void updateBatchToDelivered_shouldUpdateAllWiredMessages() throws Exception {
        Date d1 = TestUtils.date(2012, 1, 1);
        Date d2 = TestUtils.date(2012, 1, 2);
        Date d3 = TestUtils.date(2012, 1, 3);
        m_dao.updateBatchToDelivered(Arrays.asList(-81, -82, -83), Arrays.asList(d1, d2, d3));

        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, -81);
        assertThat(message1, hasEntry("status", "D"));
        assertThat(message1, hasEntry("modified_on", d1));
        Map<String, Object> message2 = fetchSingleById(Table.MESSAGE, -82);
        assertThat(message2, hasEntry("status", "D"));
        assertThat(message2, hasEntry("modified_on", d2));
        Map<String, Object> message3 = fetchSingleById(Table.MESSAGE, -83);
        assertThat(message3, hasEntry("status", "D"));
        assertThat(message3, hasEntry("modified_on", d3));
    }

    /**
     * @see MessageDao#updateBatchToFailed(Iterable)
     */
    @Test
    public void updateBatchToFailed_shouldUpdateAllWiredMessages() throws Exception {
        m_dao.updateBatchToFailed(Arrays.asList(-81, -82, -83));

        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, -81);
        assertThat(message1, hasEntry("status", "F"));
        Map<String, Object> message2 = fetchSingleById(Table.MESSAGE, -82);
        assertThat(message2, hasEntry("status", "F"));
        Map<String, Object> message3 = fetchSingleById(Table.MESSAGE, -83);
        assertThat(message3, hasEntry("status", "F"));
    }

    @Test
    public void getBroadcastStatusCounts() {
        List<Map<String, Object>> res = m_dao.getBroadcastStatusCounts(-71);
        assertThat(res, hasSize(3));
        //assertThat(res, hasEntry("W", 1));
        //assertThat(res, hasEntry("S", 1));
        //assertThat(res, hasEntry("D", 1));
    }
}