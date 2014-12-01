package io.rapidpro.mage.dao;

import org.skife.jdbi.v2.sqlobject.Bind;
import org.skife.jdbi.v2.sqlobject.GetGeneratedKeys;
import org.skife.jdbi.v2.sqlobject.SqlQuery;
import org.skife.jdbi.v2.sqlobject.SqlUpdate;
import org.skife.jdbi.v2.sqlobject.customizers.Mapper;
import org.skife.jdbi.v2.util.IntegerMapper;

/**
 * DAO for user operations
 */
public interface UserDao {

    @SqlQuery("SELECT id AS user_id FROM " + Table.USER + " WHERE username = :username")
    @Mapper(IntegerMapper.class)
    Integer getUserId(@Bind("username") String username);

    @SqlUpdate(
            "INSERT INTO " + Table.USER + " (is_active, username, password, first_name, last_name, email, is_staff, is_superuser, last_login, date_joined) " +
            "VALUES(TRUE, :username, '', '', '', :email, FALSE, FALSE, NOW(), NOW())"
    )
    @GetGeneratedKeys
    int insertUser(@Bind("username") String username, @Bind("email") String email);
}