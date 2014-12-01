package io.rapidpro.mage.dao.mapper;

import io.rapidpro.mage.util.JsonUtils;
import org.skife.jdbi.v2.sqlobject.Binder;
import org.skife.jdbi.v2.sqlobject.BinderFactory;
import org.skife.jdbi.v2.sqlobject.BindingAnnotation;

import java.lang.annotation.Annotation;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Allows binding of JSON object node arguments in DAO methods, e.g. @BindJson("config") ObjectNode config
 * Bound value is the serialized JSON of the node.
 */
@BindingAnnotation(BindJson.JsonBinderFactory.class)
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.PARAMETER})
public @interface BindJson {

    String value();

    public static class JsonBinderFactory implements BinderFactory {
        public Binder build(Annotation annotation) {
            return (q, _annotation, obj) -> {
                BindJson bind = (BindJson) _annotation;
                q.bind(bind.value(), JsonUtils.encode(obj, true));
            };
        }
    }
}