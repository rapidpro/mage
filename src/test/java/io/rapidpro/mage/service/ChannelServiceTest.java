package io.rapidpro.mage.service;

import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import java.util.List;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.service.ChannelService}
 */
public class ChannelServiceTest extends BaseServicesTest {

    private ChannelService m_service = getServices().getChannelService();

    /**
     * @see ChannelService#getChannelsByType(io.rapidpro.mage.core.ChannelType)
     */
    @Test
    public void getChannelsByType() {
        List<ChannelContext> nexmo = m_service.getChannelsByType(ChannelType.NEXMO);
        assertThat(nexmo, hasSize(1));
        assertThat(nexmo.get(0).getChannelId(), is(-42));
        assertThat(nexmo.get(0).getChannelUuid(), is("B8E3F824-D4B3-4A59-91E1-45BFF6D74263"));
        assertThat(nexmo.get(0).getChannelType(), is(ChannelType.NEXMO));
        assertThat(nexmo.get(0).getChannelConfig(), nullValue());
        assertThat(nexmo.get(0).getOrgId(), is(-11));
        List<ChannelContext> twitter = m_service.getChannelsByType(ChannelType.TWITTER);
        assertThat(twitter, hasSize(2));
    }
}