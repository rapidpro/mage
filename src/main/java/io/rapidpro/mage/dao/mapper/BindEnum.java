package io.rapidpro.mage.dao.mapper;

import org.skife.jdbi.v2.sqlobject.Binder;
import org.skife.jdbi.v2.sqlobject.BinderFactory;
import org.skife.jdbi.v2.sqlobject.BindingAnnotation;

import java.lang.annotation.Annotation;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Allows binding of enum arguments in DAO methods, e.g. @BindEnum("channelType") ChannelType type
 * Bound value is the toString return value of the enum.
 */
@BindingAnnotation(BindEnum.EnumBinderFactory.class)
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.PARAMETER})
public @interface BindEnum {

    String value();

    public static class EnumBinderFactory implements BinderFactory {
        public Binder build(Annotation annotation) {
            return (q, _annotation, _enum) -> {
                BindEnum bind = (BindEnum) _annotation;
                q.bind(bind.value(), _enum.toString());
            };
        }
    }
}