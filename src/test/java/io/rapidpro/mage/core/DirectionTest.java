package io.rapidpro.mage.core;

import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.core.Direction}
 */
public class DirectionTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.core.Direction#fromString(String)
     */
    @Test
    public void fromCode() {
        assertThat(Direction.fromString("I"), is(Direction.INCOMING));
        assertThat(Direction.fromString("O"), is(Direction.OUTGOING));
    }

    /**
     * @see Direction#fromString(String)
     */
    @Test(expected = IllegalArgumentException.class)
    public void fromCode_shouldThrowExceptionForInvalidCode() {
        Direction.fromString("X");
    }
}