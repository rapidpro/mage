package io.rapidpro.mage.core;

import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.core.Org}
 */
public class OrgTest {

    /**
     * @see io.rapidpro.mage.core.Org#getLockKey(io.rapidpro.mage.core.Org.OrgLock, String)
     */
    @Test
    public void getLockKey() {
        Org org = new Org(3, null);
        assertThat(org.getLockKey(Org.OrgLock.CONTACTS, null), is("mage:org:3:lock:contacts"));
        assertThat(org.getLockKey(Org.OrgLock.CREDITS, null), is("mage:org:3:lock:credits"));
        assertThat(org.getLockKey(Org.OrgLock.CHANNELS, null), is("mage:org:3:lock:channels"));
        assertThat(org.getLockKey(Org.OrgLock.FIELD, "age"), is("mage:org:3:lock:field:age"));
    }
}