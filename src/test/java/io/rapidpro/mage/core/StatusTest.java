package io.rapidpro.mage.core;

import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.core.Status}
 */
public class StatusTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.core.Status#fromString(String)
     */
    @Test
    public void fromCode() {
        assertThat(Status.fromString("W"), is(Status.WIRED));
        assertThat(Status.fromString("S"), is(Status.SENT));
    }

    /**
     * @see Status#fromString(String)
     */
    @Test(expected = IllegalArgumentException.class)
    public void fromCode_shouldThrowExceptionForInvalidCode() {
        Status.fromString("X");
    }
}