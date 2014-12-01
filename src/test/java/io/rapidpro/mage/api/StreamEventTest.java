package io.rapidpro.mage.api;

import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.api.StreamEvent}
 */
public class StreamEventTest extends BaseMageTest {

    @Test
    public void create() {
        StreamEvent event = new StreamEvent("123-234-456", StreamEvent.Result.ADDED, "desc");
        assertThat(event.getChannelUuid(), is("123-234-456"));
        assertThat(event.getResult(), is(StreamEvent.Result.ADDED));
        assertThat(event.getDescription(), is("desc"));
    }
}