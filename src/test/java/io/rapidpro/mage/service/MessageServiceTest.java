package io.rapidpro.mage.service;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.temba.TembaRequest;
import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.temba.request.HandleMessageRequest;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

import java.util.Date;
import java.util.Map;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.service.MessageService}
 */
public class MessageServiceTest extends BaseServicesTest {

    private MessageService m_service = getServices().getMessageService();

    /**
     * @see MessageService#getCallbackContext(int)
     */
    @Test
    public void getCallbackContext_byMessageId() {
        CallbackContext context = m_service.getCallbackContext(-81);
        assertThat(context.getMessageId(), is(-81));
        assertThat(context.getMessageStatus(), is(Status.WIRED));
        assertThat(context.getOrgId(), is(-11));
        assertThat(context.getOrgConfig().get("ACCOUNT_SID").textValue(), is("ACe0da56e18798f1bdd9569def026e2ee7"));
        assertThat(context.getOrgConfig().get("ACCOUNT_TOKEN").textValue(), is("6abb5cfa9f8b9018516cb6159088ef8d"));
        assertThat(context.getBroadcastId(), is(-71));

        // check non-existent message
        assertThat(m_service.getCallbackContext(13), nullValue());
    }

    /**
     * @see MessageService#getCallbackContext(String, io.rapidpro.mage.core.ChannelType, String)
     */
    @Test
    public void getCallbackContext_byChannelUuidAndType() {
        CallbackContext context = m_service.getCallbackContext("C4C92278-586E-4B38-93C4-D413FEF43FA2", ChannelType.VUMI, "SMS84");
        assertThat(context.getMessageId(), is(-84));
        assertThat(context.getMessageStatus(), is(Status.WIRED));
        assertThat(context.getOrgId(), is(-12));
        assertThat(context.getOrgConfig().isObject(), is(true));
        assertThat(context.getBroadcastId(), is(-72));

        // check non-existent channel UUID
        assertThat(m_service.getCallbackContext("xxxxxxx", ChannelType.VUMI, "SMS84"), nullValue());
    }

    /**
     * @see MessageService#getIncomingContextByChannelAddressAndType(io.rapidpro.mage.core.ChannelType, String)
     */
    @Test
    public void getIncomingContextByChannelAddressAndType() {
        IncomingContext context = m_service.getIncomingContextByChannelAddressAndType(ChannelType.TWILIO, "+250111111111");
        assertThat(context.getChannelId(), is(-41));
        assertThat(context.getChannelCountry(), is("RW"));
        assertThat(context.getOrgId(), is(-11));
        assertThat(context.getOrgConfig().get("ACCOUNT_SID").textValue(), is("ACe0da56e18798f1bdd9569def026e2ee7"));
        assertThat(context.getOrgConfig().get("ACCOUNT_TOKEN").textValue(), is("6abb5cfa9f8b9018516cb6159088ef8d"));

        // check non-existent number
        assertThat(m_service.getIncomingContextByChannelAddressAndType(ChannelType.TWILIO, "+0000000"), nullValue());
    }

    /**
     * @see MessageService#getIncomingContextByChannelUuidAndType(String, io.rapidpro.mage.core.ChannelType)
     */
    @Test
    public void getIncomingContextByChannelUuidAndType() {
        IncomingContext context = m_service.getIncomingContextByChannelUuidAndType("A6977A60-77EE-46FD-BFFA-AE58A65150DA", ChannelType.TWILIO);
        assertThat(context.getChannelId(), is(-41));
        assertThat(context.getChannelCountry(), is("RW"));
        assertThat(context.getOrgId(), is(-11));
        assertThat(context.getOrgConfig().get("ACCOUNT_SID").textValue(), is("ACe0da56e18798f1bdd9569def026e2ee7"));
        assertThat(context.getOrgConfig().get("ACCOUNT_TOKEN").textValue(), is("6abb5cfa9f8b9018516cb6159088ef8d"));

        // fetch again - should load from redis cache this time
        context = m_service.getIncomingContextByChannelUuidAndType("A6977A60-77EE-46FD-BFFA-AE58A65150DA", ChannelType.TWILIO);
        assertThat(context.getChannelId(), is(-41));
        assertThat(context.getChannelCountry(), is("RW"));
        assertThat(context.getOrgId(), is(-11));
        assertThat(context.getOrgConfig().get("ACCOUNT_SID").textValue(), is("ACe0da56e18798f1bdd9569def026e2ee7"));
        assertThat(context.getOrgConfig().get("ACCOUNT_TOKEN").textValue(), is("6abb5cfa9f8b9018516cb6159088ef8d"));

        // check non-existent UUID
        assertThat(m_service.getIncomingContextByChannelUuidAndType("xxxx", ChannelType.TWILIO), nullValue());
    }

    /**
     * @see MessageService#createIncoming(io.rapidpro.mage.core.IncomingContext, io.rapidpro.mage.core.ContactUrn, String, java.util.Date, String, String)
     */
    @Test
    public void createIncoming() throws Exception {
        Date createdOn = new Date();

        IncomingContext context = new IncomingContext(-41, "RW", ChannelType.TWILIO, -11, null);

        // create with existing contact #1
        int message1Id = m_service.createIncoming(context, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250222"), "Hello", createdOn, "MSG7", "Bob");
        Map<String, Object> message1 = fetchSingleById(Table.MESSAGE, message1Id);
        assertThat(message1, hasEntry("text", "Hello"));
        assertThat(message1, hasEntry("contact_id", -51));
        assertThat(message1, hasEntry("direction", "I"));
        assertThat(message1, hasEntry("created_on", createdOn));
        assertThat(message1, hasEntry("external_id", "MSG7"));
        assertThat(message1, hasEntry("topup_id", null));
        assertThat(message1, hasEntry("priority", 500));

        int contact1Id = (Integer) message1.get("contact_id");
        Map<String, Object> contact1 = fetchSingleById(Table.CONTACT, contact1Id);
        assertThat(contact1, hasEntry("org_id", -11));
        assertThat(contact1, hasEntry("name", "Nicolas"));

        assertQueuedHandleRequest(message1.get("id"), false);

        // create with new contact
        int message2Id = m_service.createIncoming(context, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250111"), "World", createdOn, "MSG8", "Bob");
        Map<String, Object> message2 = fetchSingleById(Table.MESSAGE, message2Id);
        assertThat(message2, hasEntry("text", "World"));
        assertThat(message2, hasEntry("direction", "I"));
        assertThat(message2, hasEntry("created_on", createdOn));
        assertThat(message2, hasEntry("external_id", "MSG8"));
        assertThat(message1, hasEntry("topup_id", null));
        assertThat(message1, hasEntry("priority", 500));

        int contact2Id = (Integer) message2.get("contact_id");
        Map<String, Object> contact2 = fetchSingleById(Table.CONTACT, contact2Id);
        assertThat(contact2, hasEntry("org_id", -11));
        assertThat(contact2, hasEntry("name", "Bob"));

        int contactUrnId = (Integer) message2.get("contact_urn_id");
        Map<String, Object> contactURN = fetchSingleById(Table.CONTACT_URN, contactUrnId);
        assertThat(contactURN, hasEntry("urn", "tel:+250735250111"));
        assertThat(contactURN, hasEntry("channel_id", -41));

        assertQueuedHandleRequest(message2.get("id"), true);

        // try creating same message again
        int message3Id = m_service.createIncoming(context, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250111"), "World", createdOn, "MSG8", "Bob");
        assertThat(message3Id, is(message2Id));

        // check for no queued handle message request
        assertThat(getCache().listLength(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE), is(0L));

        // create Twitter message
        int messageId = m_service.createIncoming(context, new ContactUrn(ContactUrn.Scheme.TWITTER, "BillyBob"), "Tweet", createdOn, "1234567890", "Billy Bob");
        Map<String, Object> message4 = fetchSingleById(Table.MESSAGE, messageId);
        assertThat(message4, hasEntry("text", "Tweet"));
        assertThat(message4, hasEntry("direction", "I"));
        assertThat(message4, hasEntry("created_on", createdOn));
        assertThat(message4, hasEntry("external_id", "1234567890"));

        Map<String, Object> contact = fetchSingleById(Table.CONTACT, (Integer) message4.get("contact_id"));
        assertThat(contact, hasEntry("org_id", -11));
        assertThat(contact, hasEntry("name", "Billy Bob"));

        contactURN = fetchSingleById(Table.CONTACT_URN, (Integer) message4.get("contact_urn_id"));
        assertThat(contactURN, hasEntry("urn", "twitter:billybob"));
        assertThat(contactURN, hasEntry("channel_id", -41));
    }

    /**
     * @see MessageService#updateBroadcast(int)
     */
    @Test
    public void updateBroadcast_shouldBeFailedIfMoreThanHalfAreFailed() throws Exception {
        // one failed message shouldn't effect status
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'F' WHERE id = -81");
        assertThat(m_service.updateBroadcast(-71), is(Status.SENT));

        // but another will because now more than half are failed
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'F' WHERE id = -82");
        assertThat(m_service.updateBroadcast(-71), is(Status.FAILED));
    }

    /**
     * @see MessageService#updateBroadcast(int)
     */
    @Test
    public void updateBroadcast_shouldBeErroredIfMoreThanHalfAreErrored() throws Exception {
        // one errored message shouldn't effect status
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'E' WHERE id = -81");
        assertThat(m_service.updateBroadcast(-71), is(Status.SENT));

        // but another will because now more than half are errored
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'E' WHERE id = -82");
        assertThat(m_service.updateBroadcast(-71), is(Status.ERRORED));
    }

    /**
     * @see MessageService#updateBroadcast(int)
     */
    @Test
    public void updateBroadcast_shouldBeQueuedIfAnyAreQueuedOrPending() throws Exception {
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'Q' WHERE id = -81");
        assertThat(m_service.updateBroadcast(-71), is(Status.QUEUED));

        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'P' WHERE id = -81");
        assertThat(m_service.updateBroadcast(-71), is(Status.QUEUED));
    }

    /**
     * @see MessageService#updateBroadcast(int)
     */
    @Test
    public void updateBroadcast_shouldBeDeliveredIfAllAreDelivered() throws Exception {
        // two is not enough...
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'D' WHERE id IN (-82, -83)");
        assertThat(m_service.updateBroadcast(-71), is(Status.SENT));

        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'D' WHERE id IN (-81, -82, -83)");
        assertThat(m_service.updateBroadcast(-71), is(Status.DELIVERED));
    }

    /**
     * @see MessageService#updateBroadcast(int)
     */
    @Test
    public void updateBroadcast_sometimesStatusCantBeDetermined() throws Exception {
        // a ERROR, FAILED, and DELIVERED won't change the existing status
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'E' WHERE id = -81");
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'F' WHERE id = -82");
        executeSql("UPDATE " + Table.MESSAGE + " SET status = 'D' WHERE id = -83");
        assertThat(m_service.updateBroadcast(-71), nullValue());
    }

    /**
     * @see MessageService#getBroadcastStatusCounts(int)
     */
    @Test
    public void getBroadcastStatusCounts() {
        Map<Status, Long> counts = m_service.getBroadcastStatusCounts(-71);
        assertThat(counts, hasEntry(Status.QUEUED, 0L));
        assertThat(counts, hasEntry(Status.WIRED, 1L));
        assertThat(counts, hasEntry(Status.SENT, 1L));
        assertThat(counts, hasEntry(Status.DELIVERED, 1L));
    }

    /**
     * Asserts that the last item in the Temba request queue is a handle message request with the given properties
     * @param messageId the message id
     * @param newContact whether it's a new contact
     */
    protected void assertQueuedHandleRequest(Object messageId, boolean newContact) {
        TembaRequest request = JsonUtils.parse(getCache().listLPop(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE), TembaRequest.class);
        assertThat(request, instanceOf(HandleMessageRequest.class));
        assertThat(((HandleMessageRequest) request).getMessageId(), is(messageId));
        assertThat(((HandleMessageRequest) request).isNewContact(), is(newContact));
    }
}