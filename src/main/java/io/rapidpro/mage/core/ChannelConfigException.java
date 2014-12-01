package io.rapidpro.mage.core;

/**
 * Exception when channel config JSON isn't what we expect
 */
public class ChannelConfigException extends Exception {

    public ChannelConfigException(String message) {
        super(message);
    }
}