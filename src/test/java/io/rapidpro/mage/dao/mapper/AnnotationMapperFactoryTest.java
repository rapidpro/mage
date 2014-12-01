package io.rapidpro.mage.dao.mapper;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;
import org.skife.jdbi.v2.tweak.ResultSetMapper;

import javax.validation.constraints.NotNull;
import java.sql.ResultSet;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.dao.mapper.AnnotationMapperFactory}
 */
public class AnnotationMapperFactoryTest extends BaseServicesTest {

    private final AnnotationMapperFactory m_factory = new AnnotationMapperFactory();

    /**
     * @see AnnotationMapperFactory#accepts(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Test
    public void accepts_shouldAlwaysReturnTrue() {
        assertThat(m_factory.accepts(IncomingContext.class, null), is(true));
        assertThat(m_factory.accepts(String.class, null), is(true));
    }

    /**
     * @see AnnotationMapperFactory#mapperFor(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Test
    public void mapperFor_shouldMapResultSetColumnsToJsonProperties() throws Exception {
        ResultSetMapper<PartialContact> mapper = m_factory.mapperFor(PartialContact.class, null);
        ResultSet resultSet = executeQuery("SELECT * FROM " + Table.CONTACT + " WHERE id = -51");
        resultSet.next();
        PartialContact contact = mapper.map(1, resultSet, null);
        assertThat(contact.getId(), is(-51));
        assertThat(contact.getName(), is("Nicolas"));
    }

    /**
     * @see AnnotationMapperFactory#mapperFor(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Test(expected = RuntimeException.class)
    public void mapperFor_shouldThrowExceptionForViolatedNotNullConstraint() throws Exception {
        ResultSetMapper<PartialContact> mapper = m_factory.mapperFor(PartialContact.class, null);
        ResultSet resultSet = executeQuery("SELECT * FROM " + Table.CONTACT + " WHERE id = -52"); // has no name
        resultSet.next();
        mapper.map(1, resultSet, null);
    }

    /**
     * @see AnnotationMapperFactory#mapperFor(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Test(expected = RuntimeException.class)
    public void mapperFor_shouldThrowExceptionIfClassCantBeInstantiated() throws Exception {
        ResultSetMapper<WontInstantiateContact> mapper = m_factory.mapperFor(WontInstantiateContact.class, null);
        ResultSet resultSet = executeQuery("SELECT * FROM " + Table.CONTACT + " WHERE id = -51");
        resultSet.next();
        mapper.map(1, resultSet, null);
    }

    /**
     * @see AnnotationMapperFactory#mapperFor(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Test(expected = RuntimeException.class)
    public void mapperFor_shouldThrowExceptionIfEnumMissingMethods() throws Exception {
        ResultSetMapper<WithInvalidEnumContact> mapper = m_factory.mapperFor(WithInvalidEnumContact.class, null);
        ResultSet resultSet = executeQuery("SELECT * FROM " + Table.CONTACT + " WHERE id = -51");
        resultSet.next();
        mapper.map(1, resultSet, null);
    }

    /**
     * Test mappable class
     */
    public static class PartialContact {

        @JsonProperty("id")
        private int id;

        @JsonProperty("name")
        @NotNull
        private String name;

        public int getId() {
            return id;
        }

        public String getName() {
            return name;
        }
    }

    /**
     * Unmappable class because it throws an exception when instantiated
     */
    public static class WontInstantiateContact extends PartialContact {
        WontInstantiateContact() {
            throw new UnsupportedOperationException();
        }
    }

    /**
     * Unmappable class because it has an enum with no fromString to toString methods
     */
    public static class WithInvalidEnumContact extends PartialContact {
        public static enum InvalidEnum {
            YES,
            NO
        }

        @JsonProperty("status")
        private InvalidEnum m_status;

        public InvalidEnum getStatus() {
            return m_status;
        }
    }
}