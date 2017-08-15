package io.rapidpro.mage.util;

import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Assert;
import org.junit.Test;

import javax.ws.rs.core.MultivaluedHashMap;
import javax.ws.rs.core.MultivaluedMap;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.hamcrest.Matchers.hasEntry;
import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.util.MageUtils}
 */
public class MageUtilsTest extends BaseMageTest {

    @Test
    public void integration() {
        new MageUtils();
    }

    /**
     * @see MageUtils#simplifyMultivaluedMap(javax.ws.rs.core.MultivaluedMap)
     */
    @Test
    public void simplifyMultivaluedMap() {
        MultivaluedMap<String, String> in = new MultivaluedHashMap<>();
        in.put("var1", Arrays.asList("abc", "def"));
        in.put("var2", Arrays.asList("ghi"));
        in.put("var3", Collections.<String>emptyList());

        Map<String, String> simplified = MageUtils.simplifyMultivaluedMap(in);
        Assert.assertThat(simplified, hasEntry("var1", "def"));
        Assert.assertThat(simplified, hasEntry("var2", "ghi"));
    }

    /**
     * @see MageUtils#encodeMap(java.util.Map, String, String)
     */
    @Test
    public void encodeMap_shouldEncodeMapAsString() {
        Map<String, Object> in = new LinkedHashMap<>();
        Assert.assertThat(MageUtils.encodeMap(in, ":", ","), is(""));

        in.put("var1", "abc");
        Assert.assertThat(MageUtils.encodeMap(in, ":", ","), is("var1:abc"));

        in.put("var2", 1);
        in.put("var3", 'x');
        Assert.assertThat(MageUtils.encodeMap(in, ":", ","), is("var1:abc,var2:1,var3:x"));
    }

    /**
     * @see MageUtils#getFieldValue(java.lang.reflect.Field, Object)
     */
    @Test
    public void fieldValue_shouldReturnFieldValue() throws Exception {
        ContactUrn obj = new ContactUrn(ContactUrn.Scheme.TWITTERID, "12345", "billy_bob");
        assertThat(MageUtils.getFieldValue(obj.getClass().getDeclaredField("m_scheme"), obj), is(ContactUrn.Scheme.TWITTERID));
        assertThat(MageUtils.getFieldValue(obj.getClass().getDeclaredField("m_path"), obj), is("12345"));
        assertThat(MageUtils.getFieldValue(obj.getClass().getDeclaredField("m_display"), obj), is("billy_bob"));
    }
}