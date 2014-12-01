package io.rapidpro.mage.core;

import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.core.ChannelType}
 */
public class ChannelTypeTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.core.ChannelType#fromString(String)
     */
    @Test
    public void fromCode() {
        assertThat(ChannelType.fromString("T"), is(ChannelType.TWILIO));
        assertThat(ChannelType.fromString("EX"), is(ChannelType.EXTERNAL));
    }

    /**
     * @see ChannelType#fromString(String)
     */
    @Test(expected = IllegalArgumentException.class)
    public void fromCode_shouldThrowExceptionForInvalidCode() {
        ChannelType.fromString("XX");
    }
}