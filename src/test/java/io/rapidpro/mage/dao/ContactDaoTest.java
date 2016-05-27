package io.rapidpro.mage.dao;

import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.core.ContactContext;
import org.junit.Test;

import java.util.Map;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.dao.ContactDao}
 */
public class ContactDaoTest extends BaseServicesTest {

    private ContactDao m_dao = getServices().getContactService().getDao();

    /**
     * @see ContactDao#getContactContextByOrgAndUrn(int, String)
     */
    @Test
    public void getContactContextByOrgAndUrn() {
        ContactContext context1 = m_dao.getContactContextByOrgAndUrn(-11, "tel:+250735250222");
        assertThat(context1.getContactUrnId(), is(-61));
        assertThat(context1.getContactId(), is(-51));
        assertThat(context1.getChannelId(), is(-41));

        ContactContext context2 = m_dao.getContactContextByOrgAndUrn(-12, "tel:+250783835665");
        assertThat(context2.getContactUrnId(), is(-62));
        assertThat(context2.getContactId(), is(-52));
        assertThat(context2.getChannelId(), nullValue());

        // a detached URN
        ContactContext context3 = m_dao.getContactContextByOrgAndUrn(-12, "twitter:billy_bob");
        assertThat(context3.getContactUrnId(), is(-63));
        assertThat(context3.getContactId(), nullValue());
        assertThat(context3.getChannelId(), nullValue());

        assertThat(m_dao.getContactContextByOrgAndUrn(-11, "tel:+0000000"), nullValue());
    }

    /**
     * @see ContactDao#insertContact(int, int, String, String)
     */
    @Test
    public void insertContact() throws Exception {
        int contactId = m_dao.insertContact(-1, -11, "Bob", "xyz");
        Map<String, Object> contact = fetchSingleById(Table.CONTACT, contactId);
        assertThat(contact, hasEntry("org_id", -11));
        assertThat(contact, hasEntry("name", "Bob"));
        assertThat(contact, hasEntry("created_by_id", -1));
        assertThat(contact, hasEntry("is_active", true));
        assertThat(contact, hasEntry("is_test", false));
        assertThat(contact, hasEntry("is_blocked", false));
        assertThat(contact, hasEntry("is_stopped", false));
        assertThat(contact, hasEntry("uuid", "xyz"));
    }

    /**
     * @see ContactDao#insertContactUrn(int, int, String, String, String, int, int)
     */
    @Test
    public void insertContactUrn() throws Exception {
        int contactURNId = m_dao.insertContactUrn(-11, -51, "facebook:nicpottier", "facebook", "nicpottier", 50, -41);
        Map<String, Object> contactURN = fetchSingleById(Table.CONTACT_URN, contactURNId);
        assertThat(contactURN.get("org_id"), is(-11));
        assertThat(contactURN.get("contact_id"), is(-51));
        assertThat(contactURN.get("urn"), is("facebook:nicpottier"));
        assertThat(contactURN.get("path"), is("nicpottier"));
        assertThat(contactURN.get("scheme"), is("facebook"));
        assertThat(contactURN.get("priority"), is(50));
        assertThat(contactURN.get("channel_id"), is(-41));
    }

    /**
     * @see ContactDao#updateContactUrn(int, Integer, Integer)
     */
    @Test
    public void updateContactUrn() throws Exception {
        m_dao.updateContactUrn(-62, -51, -41);
        Map<String, Object> contact = fetchSingleById(Table.CONTACT_URN, -61);
        assertThat(contact, hasEntry("contact_id", -51));
        assertThat(contact, hasEntry("channel_id", -41));
    }
}