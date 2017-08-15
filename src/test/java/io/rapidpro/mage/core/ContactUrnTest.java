package io.rapidpro.mage.core;

import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.core.ContactUrn}
 */
public class ContactUrnTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.core.ContactUrn#normalizeNumber(String, String)
     */
    @Test
    public void normalizeNumber() {
        assertThat(ContactUrn.normalizeNumber("0788383383", "RW"), is("+250788383383"));
        assertThat(ContactUrn.normalizeNumber("12345", "RW"), is("12345"));
        assertThat(ContactUrn.normalizeNumber("+250788383383", "KE"), is("+250788383383"));
        assertThat(ContactUrn.normalizeNumber("+250788383383", null), is("+250788383383"));
        assertThat(ContactUrn.normalizeNumber("250788383383", null), is("+250788383383"));
        assertThat(ContactUrn.normalizeNumber("2.50788383383E+11", null), is("+250788383383"));
        assertThat(ContactUrn.normalizeNumber("2.50788383383E+12", null), is("+250788383383"));
        assertThat(ContactUrn.normalizeNumber("0788383383", null), is("0788383383"));
        assertThat(ContactUrn.normalizeNumber("0788383383", "ZZ"), is("0788383383"));
        assertThat(ContactUrn.normalizeNumber("(917) 992-5253", "US"), is("+19179925253"));
        assertThat(ContactUrn.normalizeNumber("MTN", "RW"), is("mtn"));
    }

    /**
     * @see io.rapidpro.mage.core.ContactUrn#normalize(String)
     */
    @Test
    public void normalize() {
        assertThat(new ContactUrn(ContactUrn.Scheme.TEL, "0788383383", null).normalize("RW"), is(new ContactUrn(ContactUrn.Scheme.TEL, "+250788383383", null)));
        assertThat(new ContactUrn(ContactUrn.Scheme.TWITTER, " @BillyBob ", null).normalize(null), is(new ContactUrn(ContactUrn.Scheme.TWITTER, "billybob", null)));
        assertThat(new ContactUrn(ContactUrn.Scheme.TWITTERID, "12345", " @BillyBob").normalize(null), is(new ContactUrn(ContactUrn.Scheme.TWITTERID, "12345", "billybob")));
    }

    /**
     * @see ContactUrn#toString()
     */
    @Test
    public void test_toString() {
        assertThat(new ContactUrn(ContactUrn.Scheme.TEL, "+1234", null).toString(), is("tel:+1234"));
        assertThat(new ContactUrn(ContactUrn.Scheme.TWITTER, "billy_bob", null).toString(), is("twitter:billy_bob"));
        assertThat(new ContactUrn(ContactUrn.Scheme.TWITTERID, "12345", "billy_bob").toString(), is("twitterid:12345#billy_bob"));
    }
}