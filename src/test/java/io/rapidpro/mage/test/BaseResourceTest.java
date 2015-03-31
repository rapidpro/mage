package io.rapidpro.mage.test;

import io.rapidpro.mage.resource.BaseResource;
import io.rapidpro.mage.util.JsonUtils;
import io.dropwizard.testing.junit.ResourceTestRule;
import org.junit.Ignore;
import org.junit.Rule;

import javax.ws.rs.Path;
import javax.ws.rs.client.WebTarget;

/**
 * Base class for resource tests
 */
@Ignore
public abstract class BaseResourceTest<R extends BaseResource> extends BaseServicesTest {

    protected final R m_resource = getResource();

    protected String m_resourcePath;

    @Rule
    public final ResourceTestRule m_resourceRule = ResourceTestRule.builder().addResource(m_resource).build();

    public BaseResourceTest() {
        Path path = m_resource.getClass().getAnnotation(Path.class);
        m_resourcePath = path.value();

        JsonUtils.disableMapperAutoDetection(m_resourceRule.getObjectMapper());
    }

    /**
     * Creates a client web resource to the resource's path
     * @return the web resource
     */
    protected WebTarget resourceRequest() {
        return resourceRequest("");
    }

    /**
     * Creates a client web resource to the resource's path
     * @param path additional path
     * @return the web resource
     */
    protected WebTarget resourceRequest(String path) {
        return m_resourceRule.client().target(m_resourcePath).path(path);
    }

    public String getResourcePath() {
        return m_resourcePath;
    }

    /**
     * Sub classes need to implement this to provide the resource instance to test
     * @return the resource instance
     */
    protected abstract R getResource();
}