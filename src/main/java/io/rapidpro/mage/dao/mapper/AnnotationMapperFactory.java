package io.rapidpro.mage.dao.mapper;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.rapidpro.mage.util.JsonUtils;
import org.skife.jdbi.v2.ResultSetMapperFactory;
import org.skife.jdbi.v2.StatementContext;
import org.skife.jdbi.v2.tweak.ResultSetMapper;

import javax.validation.constraints.NotNull;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Mapper factory that produces @JsonProperty annotation based result mappers for all our model classes
 */
public class AnnotationMapperFactory implements ResultSetMapperFactory {

    /**
     * @see org.skife.jdbi.v2.ResultSetMapperFactory#accepts(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Override
    public boolean accepts(Class clazz, StatementContext statementContext) {
        return true; // default for all of our model classes
    }

    /**
     * @see org.skife.jdbi.v2.ResultSetMapperFactory#mapperFor(Class, org.skife.jdbi.v2.StatementContext)
     */
    @Override
    public ResultSetMapper mapperFor(Class clazz, StatementContext statementContext) {
        return (i, resultSet, context) -> {
            try {
                Object obj = clazz.newInstance();

                for (Field field : clazz.getDeclaredFields()) {
                    JsonProperty propertyAnnotation = field.getAnnotation(JsonProperty.class);
                    if (propertyAnnotation != null) {
                        String propertyKey = propertyAnnotation.value();
                        field.setAccessible(true);

                        Object val;

                        if (field.getType().equals(ObjectNode.class)) {
                            val = JsonUtils.parseObject(resultSet.getString(propertyKey));
                        }
                        else if (field.getType().equals(JsonNode.class)) {
                            val = JsonUtils.parse(resultSet.getString(propertyKey));
                        }
                        else if (field.getType().isEnum()) {
                            String strVal = resultSet.getString(propertyKey);
                            try {
                                Method fromString = field.getType().getMethod("fromString", String.class);
                                val = strVal != null ? fromString.invoke(null, strVal) : null;
                            }
                            catch (NoSuchMethodException ex) {
                                throw new RuntimeException("Enum type " + field.getType() + " has no fromString method", ex);
                            }
                        }
                        else {
                            val = resultSet.getObject(propertyKey);
                        }

                        NotNull notNullAnnotation = field.getAnnotation(NotNull.class);
                        if (notNullAnnotation != null && val == null) {
                            throw new RuntimeException("Property " + propertyKey + " cannot ne null");
                        }

                        field.set(obj, val);
                    }
                }

                return obj;
            }
            catch (Exception e) {
                throw new RuntimeException(e);
            }
        };
    }
}