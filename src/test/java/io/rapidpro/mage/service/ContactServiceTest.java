package io.rapidpro.mage.service;

import io.rapidpro.mage.core.ContactContext;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import java.util.Map;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.service.ContactService}
 */
public class ContactServiceTest extends BaseServicesTest {

    private ContactService m_service = getServices().getContactService();

    /**
     * @see ContactService#getOrCreateContact(int, io.rapidpro.mage.core.ContactUrn, Integer, String)
     */
    @Test
    public void getOrCreateContact() throws Exception {
        // new contact
        ContactContext context1 = m_service.getOrCreateContact(-11, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250333", null), -41, "Bob");
        assertThat(context1.isNewContact(), is(true));

        Map<String, Object> contact1 = fetchSingleById(Table.CONTACT, context1.getContactId());
        assertThat(contact1, hasEntry("org_id", -11));
        assertThat(contact1, hasEntry("name", "Bob"));
        assertThat(contact1, hasEntry("created_by_id", -3));
        assertThat(contact1, hasEntry("modified_by_id", -3));

        Map<String, Object> contact1Urn = fetchSingleById(Table.CONTACT_URN, context1.getContactUrnId());
        assertThat(contact1Urn, hasEntry("identity", "tel:+250735250333"));
        assertThat(contact1Urn, hasEntry("path", "+250735250333"));
        assertThat(contact1Urn, hasEntry("scheme", "tel"));
        assertThat(contact1Urn, hasEntry("org_id", -11));
        assertThat(contact1Urn, hasEntry("channel_id", -41));

        // same details so should return existing but also update channel
        ContactContext context2 = m_service.getOrCreateContact(-11, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250333", null), -42, "Bobby");
        assertThat(context2.getContactId(), is(context1.getContactId())); // same contact object
        assertThat(context2.getContactUrnId(), is(context1.getContactUrnId())); // same URN object
        assertThat(context2.isNewContact(), is(false));

        Map<String, Object> contact2 = fetchSingleById(Table.CONTACT, context2.getContactId());
        assertThat(contact2, hasEntry("org_id", -11));
        assertThat(contact2, hasEntry("name", "Bob")); // name not changed

        Map<String, Object> contact2Urn = fetchSingleById(Table.CONTACT_URN, context2.getContactUrnId());
        assertThat(contact2Urn, hasEntry("channel_id", -42));

        // block (i.e. archive) the contact
        executeSql("UPDATE " + Table.CONTACT + " SET is_blocked = TRUE WHERE id = " + context1.getContactId());

        ContactContext context3 = m_service.getOrCreateContact(-11, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250333", null), -42, "Bobby");
        assertThat(context3.getContactId(), is(context1.getContactId())); // same contact object
        assertThat(context3.getContactUrnId(), is(context1.getContactUrnId())); // same URN object
        assertThat(context3.isNewContact(), is(false));

        // remove contact (deactivate and detach all URNS)
        executeSql("UPDATE " + Table.CONTACT + " SET is_active = FALSE WHERE id = " + context1.getContactId());
        executeSql("UPDATE " + Table.CONTACT_URN + " SET contact_id = NULL WHERE contact_id = " + context1.getContactId());

        // try fetching the now orphaned URN (and change the channel again)
        ContactContext context4 = m_service.getOrCreateContact(-11, new ContactUrn(ContactUrn.Scheme.TEL, "+250735250333", null), -41, "Jim");
        assertThat(context4.getContactId(), not(context1.getContactId())); // new contact object
        assertThat(context4.getContactUrnId(), is(context1.getContactUrnId())); // same URN object
        assertThat(context4.isNewContact(), is(true));

        Map<String, Object> contact4 = fetchSingleById(Table.CONTACT, context4.getContactId());
        assertThat(contact4, hasEntry("org_id", -11));
        assertThat(contact4, hasEntry("name", "Jim"));
        assertThat(contact4, hasEntry("created_by_id", -3));
        assertThat(contact4, hasEntry("modified_by_id", -3));
        assertThat(contact4, hasEntry("is_blocked", false));
        assertThat(contact4, hasEntry("is_active", true));

        Map<String, Object> contact4Urn = fetchSingleById(Table.CONTACT_URN, context4.getContactUrnId());
        assertThat(contact4Urn, hasEntry("identity", "tel:+250735250333"));
        assertThat(contact4Urn, hasEntry("path", "+250735250333"));
        assertThat(contact4Urn, hasEntry("scheme", "tel"));
        assertThat(contact4Urn, hasEntry("org_id", -11));
        assertThat(contact4Urn, hasEntry("channel_id", -41));
    }
}