package io.rapidpro.mage.service;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.dao.UserDao;

/**
 * Service for user operations
 */
public class UserService extends BaseService<UserDao> {

    public UserService(ServiceManager manager, Cache cache, UserDao dao) {
        super(manager, cache, dao);
    }

    /**
     * Gets or creates the user to use for service operations
     * @return the user id
     */
    public int getOrCreateServiceUser() {
        Integer userId = getDao().getUserId(MageConstants.ServiceUser.USERNAME);

        if (userId == null) {
            userId = getDao().insertUser(MageConstants.ServiceUser.USERNAME, MageConstants.ServiceUser.EMAIL);
        }
        return userId;
    }
}