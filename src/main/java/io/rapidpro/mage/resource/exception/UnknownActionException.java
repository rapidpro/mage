package io.rapidpro.mage.resource.exception;

/**
 * Special case 400 where we don't recognize the action the channel is asking for
 */
public class UnknownActionException extends BadRequestException {

    public UnknownActionException(String action) {
        super("Unknown action: '" + action + "'");
    }
}